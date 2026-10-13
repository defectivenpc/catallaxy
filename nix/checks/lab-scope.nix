# What crosses between a cluster and the lab around it.
#
# The floe library's own suite pins the mechanism — inclusion, sealing, a
# parent filling a declared hole, an export naming a unit that is there. What
# it cannot pin is the *assembly*, because the library has no idea what a
# cluster or a lab is: that a cluster's claim is a unit beside it, that the
# claim it gets is its own, and that the descriptor reaches elaboration.
#
# Every case here is invisible at runtime. A cluster handed the wrong claim
# renders manifests that apply cleanly and point at another cluster.
#
# This file used to be twice the size and most of it checked mechanisms that
# are gone. It pinned a *scope* — entries offered per cluster, nearer-wins, a
# lab-wide collision check — and then, after that went, the shape of an
# offer: that `provides = [ "unit/promise" ]` named something real, that two
# offers nobody read were fine, that a signature absent from a table of
# crossable forms was refused. A cluster declares its own `requires`,
# `provides` and `exports` now, so:
#
#   - an export naming a unit that is not there is the library's refusal,
#     with the units listed (`floes/lib/refusals.nix`);
#   - a declared hole nothing inside reads is the library's too, the other
#     direction of the same check;
#   - two clusters exporting one signature is an ordinary ambiguity, refused
#     at the hole that could not choose rather than lab-wide;
#   - which fields cross is the export signature the author chose, so there
#     is no table left to be absent from. That check is genuinely gone, and
#     `floes/tests/netbird-operator.nix` records what was lost with it.
#
# What is left is what only an assembly can be wrong about.
{
  lib,
  pkgs,
  mkLab,
  labDefs,
  catallaxy,
  floes,
}:

let
  inherit (import ../../lib/lower/cluster.nix { inherit lib catallaxy; }) placeCluster;

  # Ports and subnets differ per lab because two labs evaluated in one
  # expression are still two labs, and the host-port checks are real.
  mkScopeLab =
    {
      name,
      subnet,
      dnsPort,
      units ? { },
      clusters,
    }:
    mkLab (
      catallaxy.mkLabFloe
        {
          inherit name;
          summary = "A lab assembled for one case of the lab/cluster boundary.";
          units = _: units;
          clusters = _: clusters;
        }
        {
          inherit name subnet;

          zone = "${name}.test";
          zonePort = dnsPort;
        }
    );

  # A cluster floe with nothing in it but what a case needs.
  #
  # `kapp` because every cluster must say how its content reaches it, and
  # `gateway-api-crds` because something inside has to *read* the claim — a
  # declared hole nothing reads is refused by the library, which is the other
  # direction of the check that an export must name a unit that is there.
  # Both are the cheapest floe that does its job.
  mkTestCluster =
    {
      name,
      units ? { },
      requires ? { },
      provides ? { },
      exports ? { },
    }:
    catallaxy.mkClusterFloe {
      name = "lab-scope-${name}";
      summary = "A cluster assembled for one case of the lab/cluster boundary.";

      requires = {
        claim = catallaxy.sigs.KUBERNETES_CLUSTER;
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

      units =
        _:
        {
          kapp = floes.kapp { };
          gateway-api = floes.gateway-api-crds { };
        }
        // units;
    };

  refuses = l: !(builtins.tryEval (builtins.deepSeq l.cliConfig "evaluated")).success;

  # ---- downward: a fact the lab holds reaches a cluster -------------------

  # `coredns-zone` is the whole downward path in one floe: it requires
  # `DNS_ZONE`, takes no inputs at all, and every field it renders came from
  # the lab.
  dnsLab = mkScopeLab {
    name = "scope-dns";
    subnet = "172.31.0.0/16";
    dnsPort = 5373;
    clusters.core = {
      floe = mkTestCluster {
        name = "dns";
        requires.zone = catallaxy.sigs.DNS_ZONE;
        units.coredns-zone = floes.coredns-zone { };
      } { };

      claim = floes.k3d-cluster { };
    };
  };

  corednsCustom =
    dnsLab.clusters.core.out.bundles."coredns-zone/coredns".resources.coredns-custom.data."lab.server";

  # ---- the claim is a unit beside its cluster ----------------------------

  # Two clusters, each leaving `KUBERNETES_CLUSTER` open, each with a claim of
  # its own. Nothing a deployer writes says which claim answers which cluster:
  # writing it under the cluster is the whole of saying so, and the submodule
  # binds the hole. Get that wrong and both clusters resolve one descriptor —
  # two kubeconfigs that are the same kubeconfig, which every render and every
  # digest accepts.
  twoClusters = mkScopeLab {
    name = "scope-claims";
    subnet = "172.30.0.0/16";
    dnsPort = 5374;
    clusters = {
      core = {
        floe = mkTestCluster { name = "core"; } { };
        claim = floes.k3d-cluster { podSubnet = "10.244.0.0/16"; };
      };

      obs = {
        floe = mkTestCluster { name = "obs"; } { };
        claim = floes.k3d-cluster { podSubnet = "10.245.0.0/16"; };
      };
    };
  };

  claimOf = c: lib.head (lib.attrValues twoClusters.clusters.${c}.out.cluster);

  # A cluster floe whose claim is not open has nothing for the claim written
  # beside it to answer, and the submodule says so by name rather than letting
  # the claim become a unit nothing reads.
  sealedClaim = mkScopeLab {
    name = "scope-sealed";
    subnet = "172.29.0.0/16";
    dnsPort = 5375;
    clusters.core = {
      floe = catallaxy.mkClusterFloe {
        name = "lab-scope-sealed";
        summary = "A cluster that creates its own claim, which a lab cannot place.";
        provides.delivery = catallaxy.sigs.DELIVERY_POLICY;
        exports.delivery = "kapp/delivery";
        units = _: {
          kapp = floes.kapp { };
          cluster = floes.k3d-cluster { };
        };
      } { };

      claim = floes.k3d-cluster { };
    };
  };

  # ---- upward: what a cluster reads of a sibling -------------------------

  # A cluster that reads something another cluster holds has to declare the
  # hole, and the refusal names the signature and the inclusion. This is the
  # case that caught `homelab.mesh` and `tests/secret-sharing` independently
  # while they were being written — under the old mechanism neither
  # declaration existed anywhere, and resolution found the value by searching.
  undeclaredRead = mkScopeLab {
    name = "scope-undeclared";
    subnet = "172.28.0.0/16";
    dnsPort = 5376;
    clusters = {
      core = {
        floe = mkTestCluster {
          name = "mesh-holder";
          units.netbird = floes.netbird { };
          provides.mesh = catallaxy.sigs.MESH_NETWORK_SHARED;
          exports.mesh = "netbird/mesh";
        } { };

        claim = floes.k3d-cluster { podSubnet = "10.244.0.0/16"; };
      };

      obs = {
        floe = mkTestCluster {
          name = "mesh-reader";
          units.netbird-operator = floes.netbird-operator { };
        } { };

        claim = floes.k3d-cluster { podSubnet = "10.245.0.0/16"; };
      };
    };
  };

  # ---- the shipped lab that actually crosses -----------------------------
  #
  # Everything above is a fixture bent one way at a time. This is
  # `homelab.mesh` as it ships: `core` runs netbird and exports the mesh in
  # its shared form, `obs` declares `requires.mesh` and runs an operator.
  mesh = labDefs."homelab.mesh".clusters;

  operatorValues =
    cluster: mesh.${cluster}.out.bundles."netbird-operator/operator".helmCharts.netbird-operator.values;

  results = lib.runTests {

    # Placement re-instantiates a claim to fill in what only placement knows,
    # and `instantiate` returns a fresh instance — so a binding a deployer
    # wrote has to be carried over by hand. Dropped, it is an unwired hole and
    # no word about why: no lab in this tree binds a claim, so nothing else
    # here would fail.
    testPlacementKeepsAClaimsBindings = {
      expr =
        (placeCluster {
          clusterName = "core";
          labName = "scope-bindings";
          floe = mkTestCluster { name = "bindings"; } { };
          claim = (floes.external-cluster { context = "x"; }).bind { labStore = "somewhere"; };
        }).claim.bindings;
      expected = {
        labStore = "somewhere";
      };
    };

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

    testEachClusterResolvesItsOwnClaim = {
      expr = {
        core = (claimOf "core").network.podSubnet;
        obs = (claimOf "obs").network.podSubnet;
      };
      expected = {
        core = "10.244.0.0/16";
        obs = "10.245.0.0/16";
      };
    };

    testTheClaimsDescriptorReachesTheCluster = {
      expr = lib.length (lib.attrValues twoClusters.clusters.core.out.cluster);
      expected = 1;
    };

    testAClusterThatSealsItsClaimIsRefused = {
      expr = refuses sealedClaim;
      expected = true;
    };

    testReadingASiblingUndeclaredIsRefused = {
      expr = refuses undeclaredRead;
      expected = true;
    };

    testTheShippedLabCrossesTheMesh = {
      expr = (operatorValues "obs").managementURL == (operatorValues "core").managementURL;
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
