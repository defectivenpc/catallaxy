# Two clusters agreeing on an address without talking to each other.
#
# The positive cases read the rendered `secret-sharing` fixture: the whole
# design is that neither side reads the other's output, so the only way to
# check they agree is to render both and compare.
#
# The negative cases matter more. Every one of them has no runtime symptom
# short of an ExternalSecret waiting forever on a key nothing wrote, which is
# indistinguishable from a store that is merely slow.
{
  lib,
  pkgs,
  labDefs,
  mkLab,
}:

let
  shared = labDefs."secret-sharing".config.lab.clusters;

  resourcesOf =
    cluster: bundle: (shared.${cluster}.out.bundles.${bundle} or { resources = { }; }).resources;

  push = (resourcesOf "core" "secret-publication/lab-ca-ca-secret").push or null;
  pull = (resourcesOf "obs" "secret-subscription/lab-ca-ca-secret").pull or null;

  # A minimal two-cluster lab, so a case can bend one thing and leave the rest
  # correct. Everything a store needs is here; what varies is passed in.
  labWith =
    {
      stores,
      core ? { },
      obs ? { },
    }:
    mkLab {
      modules = [
        (
          { config, floes, ... }:
          let
            cluster = clusterName: {
              cluster = floes.k3d-cluster {
                name = clusterName;
                instanceName = "refuse-${clusterName}";
              };
              external-secrets = floes.external-secrets {
                chart = "/dev/null";
                crds = "/dev/null";
              };
              store = floes.secret-store {
                labStore = "runtime";
                server = "https://vault.refuse.test";
              };

              # So there is a Secret that genuinely exists to publish. Without
              # it every case below fails the cluster's "who creates this
              # Secret" check instead of the thing it means to test, and the
              # refusals all pass for the wrong reason.
              cert-manager = floes.cert-manager { chart = "/dev/null"; };
            };

            project.vault-token = {
              source = "cred";
              namespace = "external-secrets";
              keys.token.from = "token";
            };
          in
          {
            lab.name = "refuse";
            lab.network.subnet = "172.29.0.0/16";

            lab.secrets.stores = stores;
            lab.secrets.managed.cred = {
              store = "authored";
              keys.token.generator = "hex";
              keys.token.length = 16;
            };

            lab.clusters.core = {
              floes = cluster "core";
              secrets = {
                inherit project;
              }
              // core;
            };
            lab.clusters.obs = {
              floes = cluster "obs";
              secrets = {
                inherit project;
              }
              // obs;
            };
          }
        )
      ];
    };

  bothStores = {
    authored.backend = "sops";
    runtime = {
      backend = "vault";
      vault.server = "https://vault.refuse.test";
    };
  };

  # `tryEval` catches the assertion `lib/lab.nix` throws. `deepSeq` because
  # the failure is inside a lazily-built attribute.
  refuses =
    lab: !(builtins.tryEval (builtins.deepSeq lab.config.lab.out.cliConfig "evaluated")).success;

  publishesCa = {
    publish.lab-ca-ca-secret.namespace = "cert-manager";
  };

  results = lib.runTests {
    # ---- the two sides agree, unprompted -------------------------------

    testThePublisherDerivesTheAddressFromItsOwnIdentity = {
      expr = (lib.head push.spec.data).match.remoteRef.remoteKey;
      expected = "secret-sharing/core/cert-manager/lab-ca-ca-secret";
    };

    testTheSubscriberDerivesTheSameAddressFromTheClusterItNames = {
      expr = (lib.head pull.spec.dataFrom).extract.key;
      expected = "secret-sharing/core/cert-manager/lab-ca-ca-secret";
    };

    # The address names the producing cluster, never the consuming one: a
    # value means "the credential core minted", and two clusters publishing
    # the same name are two different values.
    testTheAddressNamesTheProducer = {
      expr = lib.hasInfix "/core/" (lib.head pull.spec.dataFrom).extract.key;
      expected = true;
    };

    # The subscriber never spells the producer's namespace or Secret name; it
    # reads them off the producer's own declaration.
    testTheSubscriberMaterialisesUnderItsOwnName = {
      expr = pull.spec.target.name;
      expected = "core-lab-ca";
    };

    testPublishingNoNamedKeysPushesTheSecretWhole = {
      expr = (lib.head push.spec.data).match ? secretKey;
      expected = false;
    };

    # What reads a Secret often finds it by label rather than by name.
    testLabelsReachTheMaterialisedSecret = {
      expr = pull.spec.target.template.metadata.labels;
      expected = {
        "catallaxy.io/trust" = "lab-ca";
      };
    };

    # Both sides name the same ClusterSecretStore, derived from the lab store
    # rather than configured on either.
    testBothSidesNameTheSameStore = {
      expr = (lib.head push.spec.secretStoreRefs).name == pull.spec.secretStoreRef.name;
      expected = true;
    };

    # A generator reruns on every refresh; a subscription must not.
    testTheSubscriptionRefreshesRatherThanReminting = {
      expr = pull.spec.refreshInterval;
      expected = "1h";
    };

    # ---- and are refused when they do not -------------------------------

    # The control, and it is not optional. Every refusal below is a `labWith`
    # that bends one thing; if the harness itself were broken they would all
    # pass while checking nothing. This is the same harness, correct, and it
    # must evaluate.
    testTheHarnessBuildsALabThatIsAccepted = {
      expr = refuses (labWith {
        stores = bothStores;
        core = publishesCa;
        obs.subscribe.lab-ca-ca-secret = {
          from = "core";
          namespace = "default";
        };
      });
      expected = false;
    };

    # Both sides derive the address from the producer's identity, so a name
    # that does not match on both leaves the ExternalSecret waiting forever.
    # Checking it is the point of naming the producer rather than asking it.
    testSubscribingToSomethingUnpublishedIsRefused = {
      expr = refuses (labWith {
        stores = bothStores;
        obs.subscribe.not-published = {
          from = "core";
          namespace = "default";
        };
      });
      expected = true;
    };

    testSubscribingFromAClusterThatIsNotInTheLabIsRefused = {
      expr = refuses (labWith {
        stores = bothStores;
        core = publishesCa;
        obs.subscribe.lab-ca-ca-secret = {
          from = "nowhere";
          namespace = "default";
        };
      });
      expected = true;
    };

    # An authored store is read-only and top-down. Publishing into one writes
    # where nothing reads.
    testPublishingIntoAnAuthoredStoreIsRefused = {
      expr = refuses (labWith {
        stores = bothStores;
        core.publish.lab-ca-ca-secret = {
          namespace = "cert-manager";
          store = "authored";
        };
      });
      expected = true;
    };

    # With no runtime store there is nothing to default to, and the message
    # has to say that rather than picking one.
    testSharingWithNoRuntimeStoreIsRefused = {
      expr = refuses (labWith {
        stores.authored.backend = "sops";
        core = publishesCa;
      });
      expected = true;
    };

    # A `ClusterSecretStore` is not shared between clusters, only the backend
    # behind it is. A publication naming a store this cluster does not install
    # is admitted and then never reconciles.
    #
    # The lab declares `elsewhere` and the cluster installs a floe for
    # `runtime`, so this bends exactly one thing from the accepted baseline:
    # everything else, including what is published, still resolves.
    testSharingThroughAStoreThisClusterDoesNotInstallIsRefused = {
      expr = refuses (labWith {
        stores = bothStores // {
          elsewhere = {
            backend = "vault";
            vault.server = "https://other.refuse.test";
          };
        };
        core.publish.lab-ca-ca-secret = {
          namespace = "cert-manager";
          store = "elsewhere";
        };
      });
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
