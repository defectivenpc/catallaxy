# The lab as a scope, from the lab's side.
#
# `lib/tests/floe-core.nix` pins the mechanism — nearer-wins, sealing, no
# ordering edge — against a fixture distribution. What it cannot pin is the
# assembly, because floe-core has no idea what a cluster or a lab is: which
# entries reach which cluster's scope, and what happens when two of them claim
# one signature.
#
# Every case here is invisible at runtime. A cluster that resolved the wrong
# provider renders manifests that apply cleanly and point somewhere else.
{
  lib,
  pkgs,
  mkLab,
  labDefs,
}:

let
  # Ports and subnets differ per lab because two labs evaluated in one
  # expression are still two labs, and the host-port checks are real.
  mkScopeLab =
    {
      name,
      subnet,
      dnsPort,
      body,
    }:
    mkLab {
      modules = [
        (
          { floes, ... }:
          lib.recursiveUpdate
            {
              lab.name = name;
              lab.network.subnet = subnet;
              lab.dns.hostPort = dnsPort;
            }
            (body {
              inherit floes;
            })
        )
      ];
    };

  # ---- downward: the lab provides ----------------------------------------

  # `lab-dns` is the whole downward path in one floe: it requires `DNS_ZONE`,
  # takes no inputs at all, and every field it renders came from the lab.
  dnsLab = mkScopeLab {
    name = "scope-dns";
    subnet = "172.31.0.0/16";
    dnsPort = 5373;
    body =
      { floes }:
      {
        lab.dns.zone = "scope-dns.test";
        lab.clusters.core.floes = {
          cluster = floes.k3d-cluster {
            name = "core";
            instanceName = "scope-dns-core";
          };
          lab-dns = floes.lab-dns { };
        };
      };
  };

  corednsCustom =
    dnsLab.config.lab.clusters.core.out.bundles."lab-dns/coredns".resources.coredns-custom.data."lab.server";

  # ---- upward: a cluster offers ------------------------------------------

  # `cert-manager` requires nothing but a cluster, and `trust-manager`
  # consumes both of its provides. That is the pair an offer-shadowing bug
  # shows up in: the cluster that offers is also the one that consumes.
  offering = mkScopeLab {
    name = "scope-offer";
    subnet = "172.30.0.0/16";
    dnsPort = 5374;
    body =
      { floes }:
      {
        lab.clusters.core = {
          floes = {
            cluster = floes.k3d-cluster {
              name = "core";
              instanceName = "scope-offer-core";
            };
            cert-manager = floes.cert-manager { chart = "/dev/null"; };
            trust-manager = floes.trust-manager { chart = "/dev/null"; };
          };
          provides = [ "cert-manager/issuance" ];
        };
      };
  };

  # Two clusters that both hold a `lab-zone`, varying only in which of them
  # offers it upward.
  #
  # `lab-zone` is the vehicle because every field of `DNS_ZONE` travels, so
  # the eager all-local refusal in `link.nix` cannot be what fires; and
  # because nothing here consumes one, neither can the exactly-one check,
  # which only runs where a hole resolves. Nothing else in these two clusters
  # can fail at all — which is what makes `refuses` mean the collision here.
  offeringZoneFrom =
    offerers:
    mkScopeLab {
      name = "scope-two";
      subnet = "172.27.0.0/16";
      dnsPort = 5375;
      body =
        { floes }:
        {
          lab.clusters = lib.genAttrs [ "core" "obs" ] (clusterName: {
            floes = {
              cluster = floes.k3d-cluster {
                name = clusterName;
                instanceName = "scope-two-${clusterName}";
              };
              zone = floes.lab-zone {
                zone = "scope-two.test";
                server = "172.27.0.1";
              };
            };
            provides = lib.optional (lib.elem clusterName offerers) "zone/zone";
          });
        };
    };

  # One cluster, one floe, nothing else that could fail — so `tryEval`
  # catching *something* can only be the offer.
  offeringOnly =
    {
      subnet,
      dnsPort,
      name,
    }:
    spec:
    mkScopeLab {
      inherit name subnet dnsPort;
      body =
        { floes }:
        {
          lab.clusters.core = {
            floes.cluster = floes.k3d-cluster {
              name = "core";
              instanceName = "${name}-core";
            };
            provides = [ spec ];
          };
        };
    };

  offeringUnit = offeringOnly {
    name = "scope-undeclared";
    subnet = "172.26.0.0/16";
    dnsPort = 5376;
  };

  # A cluster with a cert-manager, offering one promise or the other. One of
  # the two can cross and one cannot, which is the case the offer surface is
  # per promise for.
  offeringCertManager =
    spec:
    mkScopeLab {
      name = "scope-cm";
      subnet = "172.25.0.0/16";
      dnsPort = 5377;
      body =
        { floes }:
        {
          lab.clusters.core = {
            floes = {
              cluster = floes.k3d-cluster {
                name = "core";
                instanceName = "scope-cm-core";
              };
              cert-manager = floes.cert-manager { chart = "/dev/null"; };
            };
            provides = [ spec ];
          };
        };
    };

  refuses = l: !(builtins.tryEval (builtins.deepSeq l.config.lab.out.cliConfig "evaluated")).success;

  # ---- the shipped lab that actually crosses ------------------------------
  #
  # Everything above is a fixture bent one way at a time. This is `homelab.mesh`
  # as it ships: `core` runs netbird and offers `netbird/mesh`, `obs` runs an
  # operator and nothing else of the mesh.
  mesh = labDefs."homelab.mesh".config.lab.clusters;

  operatorValues =
    cluster: mesh.${cluster}.out.bundles."netbird-operator/operator".helmCharts.netbird-operator.values;

  results = lib.runTests {

    # ---- downward --------------------------------------------------------

    # The appliance, end to end: `lab.dns.zone` and `lab.dns.port` are written
    # in one place, the lab builds `lab-zone` out of the merged result, and a
    # floe in a cluster reads all three fields back. Nothing in the cluster
    # was handed a zone.
    #
    # The port is what makes this more than a rename. `lab.dns.port` defaults
    # to `hostPort`, so a lab that moves its DNS off 5354 moves what a pod
    # forwards to as well — and `every-floe` pointed external-dns at 53 for
    # exactly as long as those were two hand-passed arguments.
    testAClusterResolvesTheLabsZone = {
      expr = corednsCustom;
      expected = ''
        scope-dns.test:53 {
            errors
            cache 30
            forward . 172.31.0.1:5373
        }
      '';
    };

    # ---- upward ----------------------------------------------------------

    # A cluster that offers a unit still resolves against it itself. Nearer
    # wins, so the local unit answers before the scope is consulted at all.
    #
    # Not hypothetical. The flat threading this replaced injected every export
    # into every cluster including the exporter, where it *competed* with the
    # local one — so a cluster that offered its gateway could then no longer
    # route through it, for "two providers".
    #
    # Self-exclusion in `scopeFor` is a separate guarantee and is not what
    # this pins: it breaks the evaluation cycle a cluster reading its own link
    # result would form, which shows up as infinite recursion rather than as a
    # value a test can compare.
    testOfferingAUnitDoesNotDisplaceItAtHome = {
      expr = lib.attrNames offering.config.lab.clusters.core.link.wiring.scope.trust-manager;
      expected = [ ];
    };

    # The same claim at the value. `X509_WEBHOOK` is entirely local, so this
    # namespace reads only because the resolution stayed inside one link — had
    # it crossed, this would be the throw `sealedScope` puts there.
    testTheLocalProvideIsStillReadable = {
      expr = offering.config.lab.clusters.core.link.provides.cert-manager.webhook.namespace;
      expected = "cert-manager";
    };

    # ---- the refusals ----------------------------------------------------

    # A lab scope holds one provider per signature, so two clusters offering
    # one leaves whichever a third resolved arbitrary. Caught once here rather
    # than N-1 times as each other cluster fails to choose.
    testTwoClustersOfferingOneSignatureIsRefused = {
      expr = refuses (offeringZoneFrom [
        "core"
        "obs"
      ]);
      expected = true;
    };

    # The paired positive, and the whole reason the case above can be read as
    # a collision: the same two clusters, the same floe in both, one offer.
    testOneOfferOfTheSameSignatureIsFine = {
      expr = refuses (offeringZoneFrom [ "core" ]);
      expected = false;
    };

    # A name resolving to nothing, in each of the three ways it can. Refused
    # rather than silently contributing no entry, which is what a typo would
    # otherwise do.
    testAnOfferThatNamesNothingIsRefused = {
      expr = map (spec: refuses (offeringUnit spec)) [
        "cluster" # no promise named
        "nope/it" # no such unit
        "cluster/nope" # unit, no such promise
      ];
      expected = [
        true
        true
        true
      ];
    };

    # `X509_ISSUANCE` is a mix — `publicIssuer` is true wherever it is asked —
    # so the promise crosses even though most of its fields do not.
    testAPromiseWithSomethingPortableCanBeOffered = {
      expr = refuses (offeringCertManager "cert-manager/issuance");
      expected = false;
    };

    # `X509_WEBHOOK` is entirely local. Refused where it is offered, which is
    # where a lab author can do something about it — not in whichever cluster
    # first resolved a hole against it.
    #
    # The pair is the point of naming promises rather than units: one floe,
    # one offerable and one not.
    testAPromiseThatCannotTravelIsRefused = {
      expr = refuses (offeringCertManager "cert-manager/webhook");
      expected = true;
    };
  };
in
{
  lab-scope = pkgs.runCommand "lab-scope-tests" { } ''
    cat <<'EOF' > $out
    ${builtins.toJSON results}
    EOF
    if [ ${toString (builtins.length results)} -ne 0 ]; then
      echo "lab-scope FAILED:" >&2
      cat $out >&2
      exit 1
    fi
  '';
}
