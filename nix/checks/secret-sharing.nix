# Two clusters agreeing on an address, by one of them naming it.
#
# The design used to be that neither side read the other's output and both
# derived the same string from the producer's identity — so the only way to
# check they agreed was to render both and compare, and five assertion
# families stood in for the comparison the mechanism could not make.
#
# The producer names the key and provides it; the consumer reads it. So the
# positive case is that the rendered pair point at one key, and every negative
# case is a *mechanism* refusing rather than an assertion noticing: an
# unfilled hole, a link with no provider, a floe's own check on what it was
# handed.
{
  lib,
  pkgs,
  labDefs,
  mkLab,
  catallaxy,
  floes,
}:

let
  shared = labDefs."secret-sharing".clusters;

  resourcesOf =
    cluster: bundle: (shared.${cluster}.out.bundles.${bundle} or { resources = { }; }).resources;

  push = (resourcesOf "core" "publish-ca/publication").push or null;
  pull = (resourcesOf "obs" "subscribe-ca/subscription").pull or null;

  # Everything a store needs, shared by every case below.
  units = {
    kapp = floes.kapp { };

    external-secrets = floes.external-secrets {
      chart = "/dev/null";
      crds = "/dev/null";
    };

    store = floes.secret-store { server = "https://vault.refuse.test"; };

    projection = floes.secret-projection {
      secret = "vault-token";
      namespace = "external-secrets";
      keys.token.from = "token";
    };

    cert-manager = floes.cert-manager { chart = "/dev/null"; };
  };

  # A cluster floe per side: `core` publishes and exports what it published,
  # `obs` reads it. Authored rather than assembled, so the cases below bend one
  # declaration at a time.
  mkCluster =
    {
      name,
      extraUnits ? { },
      provides ? { },
      exports ? { },
      requires ? { },
    }:
    catallaxy.mkClusterFloe {
      name = "refuse-${name}";
      summary = "A cluster bent one way, for the secret-sharing refusals.";

      requires = {
        cluster = catallaxy.sigs.KUBERNETES_CLUSTER;

        labStore = catallaxy.sigs.LAB_SECRET_STORE;
        labSecret = catallaxy.sigs.LAB_SECRET;
      }
      // requires;

      provides = {
        delivery = catallaxy.sigs.DELIVERY_POLICY;
      }
      // provides;

      exports = {
        delivery = "kapp/delivery";
      }
      // exports;

      units = _: units // extraUnits;
    };

  provisionerFor =
    clusterName:
    floes.k3d-cluster {
      name = clusterName;
      instanceName = "refuse-${clusterName}";
    };

  # A minimal two-cluster lab, so a case can bend one thing and leave the rest
  # correct. Everything a store needs is above; what varies is passed in.
  labWith =
    {
      storeBinding ? "runtime",
      publication ? { },
      coreExports ? {
        publication = "publish-ca/publication";
      },
      obsFloes ? _: { },
    }:
    mkLab (
      catallaxy.mkLabFloe
        {
          name = "refuse";
          summary = "Two clusters sharing a secret, bent one way.";

          units = _: {
            authored = floes.lab-secret-store { backend = "sops"; };

            runtime = floes.lab-secret-store {
              backend = "vault";
              vaultServer = "https://vault.refuse.test";
            };

            cred =
              (floes.lab-authored-secret {
                keys.token.generator = "hex";
                keys.token.length = 16;
              }).bind
                { labStore = "authored"; };
          };

          clusters = _: {
            core = {
              floe =
                (mkCluster {
                  name = "core";
                  extraUnits.publish-ca = floes.secret-publication (
                    {
                      namespace = "cert-manager";
                      secret = "lab-ca-ca-secret";
                      key = "refuse/core/lab-ca";
                    }
                    // publication
                  );
                  provides = lib.mapAttrs (_: _: catallaxy.sigs.PUBLISHED_SECRET) coreExports;
                  exports = coreExports;
                } { }).bind
                  { labStore = storeBinding; };

              provisioner = provisionerFor "core";
            };

            obs = {
              floe =
                (mkCluster {
                  name = "obs";
                  extraUnits = obsFloes floes;
                  requires = lib.optionalAttrs (obsFloes floes != { }) {
                    publication = catallaxy.sigs.PUBLISHED_SECRET;
                  };
                } { }).bind
                  { labStore = "runtime"; };

              provisioner = provisionerFor "obs";
            };
          };
        }
        {
          name = "refuse";
          zone = "refuse.test";
          subnet = "172.29.0.0/16";
        }
    );

  subscriber = floes: {
    subscribe-ca = floes.secret-subscription {
      namespace = "default";
      secret = "core-lab-ca";
    };
  };

  # `tryEval` catches the assertion `lib/lab.nix` throws, and the link error
  # the floe library throws. `deepSeq` because the failure is inside a lazily
  # built attribute.
  refuses = lab: !(builtins.tryEval (builtins.deepSeq lab.cliConfig "evaluated")).success;

  results = lib.runTests {

    testThePairPointsAtOneKey = {
      expr = {
        pushes = (lib.head push.spec.data).match.remoteRef.remoteKey;
        reads = (lib.head pull.spec.dataFrom).extract.key;
      };
      expected = {
        pushes = "secret-sharing/core/lab-ca";
        reads = "secret-sharing/core/lab-ca";
      };
    };

    testEachSideUsesItsOwnStoreObject = {
      expr = {
        pushes = (lib.head push.spec.secretStoreRefs).name;
        reads = pull.spec.secretStoreRef.name;
      };
      expected = {
        pushes = "catallaxy-runtime";
        reads = "catallaxy-runtime";
      };
    };

    testTheValueLandsUnderALocalName = {
      expr = {
        whole = (lib.head push.spec.data).match ? secretKey;
        named = pull.spec.target.name;
      };
      expected = {
        whole = false;
        named = "core-lab-ca";
      };
    };

    testTheHarnessBuildsALabThatIsAccepted = {
      expr = refuses (labWith {
        obsFloes = subscriber;
      });
      expected = false;
    };

    testASubscriptionWithNoPublicationIsRefused = {
      expr = refuses (labWith {
        coreExports = { };
        obsFloes = subscriber;
      });
      expected = true;
    };

    testPublishingIntoAReadOnlyStoreIsRefused = {
      expr = refuses (labWith {
        storeBinding = "authored";
        obsFloes = subscriber;
      });
      expected = true;
    };

    testPublishingWithNoStoreInTheClusterIsRefused = {
      expr = refuses (
        mkLab (
          catallaxy.mkLabFloe
            {
              name = "refuse-nostore";
              summary = "A publication with no store in the cluster to name.";

              clusters = _: {
                core = {
                  floe = catallaxy.mkClusterFloe {
                    name = "refuse-nostore-core";
                    summary = "A publication with no store in the cluster to name.";

                    requires.cluster = catallaxy.sigs.KUBERNETES_CLUSTER;
                    provides.delivery = catallaxy.sigs.DELIVERY_POLICY;
                    exports.delivery = "kapp/delivery";

                    units = _: {
                      kapp = floes.kapp { };
                      cert-manager = floes.cert-manager { chart = "/dev/null"; };
                      publish-ca = floes.secret-publication {
                        namespace = "cert-manager";
                        secret = "lab-ca-ca-secret";
                        key = "refuse/core/lab-ca";
                      };
                    };
                  } { };

                  provisioner = floes.k3d-cluster {
                    name = "core";
                    instanceName = "refuse-nostore-core";
                  };
                };
              };
            }
            {
              name = "refuse-nostore";
              zone = "refuse-nostore.test";
              subnet = "172.30.0.0/16";
            }
        )
      );
      expected = true;
    };
  };
in
{
  secret-sharing = pkgs.runCommand "secret-sharing-tests" { } ''
    cat <<'EOF' > $out
    ${builtins.toJSON results}
    EOF
    if [ ${toString (builtins.length results)} -ne 0 ]; then
      echo "secret-sharing FAILED:" >&2
      cat $out >&2
      exit 1
    fi
  '';
}
