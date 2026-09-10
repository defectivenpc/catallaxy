# Who fronts a cluster, from the lab's side — RFC 0005 §6.4.
#
# The fixture `examples/labs/tests/self-edge.nix` pins what a lab *with* a
# self-edge cluster renders. This pins the refusals, which have no fixture
# because a lab that is refused does not render.
#
# The failure these guard against is the one the edge model was written for:
# before it, a cluster the lab was not the edge for could not be expressed at
# all, and the way it could not be expressed was an assertion about a backend
# it was never going to have.
{
  lib,
  pkgs,
  mkLab,
}:

let
  # Two clusters would need two subnets and there is only one arrangement
  # under test, so one cluster and one set of ports throughout.
  mkEdgeLab =
    { name, cluster }:
    mkLab {
      modules = [
        (
          {
            floes,
            cataCharts,
            k8sSpecs,
            ...
          }:
          {
            lab.name = name;
            lab.network.subnet = "172.41.0.0/16";
            lab.dns.hostPort = 5371;
            lab.proxy.enable = true;
            lab.proxy.httpPort = 8091;

            lab.clusters.app = cluster {
              floes = {
                cluster = floes.k3d-cluster {
                  name = "app";
                  instanceName = "${name}-app";
                };
                gateway-api = floes.gateway-api-crds {
                  manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
                  version = "v1.2.1";
                };
                cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
                gateway = floes.gateway { chart = "${cataCharts.traefik.chart}"; };
                podinfo = floes.podinfo { };
              };
            };
          }
        )
      ];
    };

  refuses = l: !(builtins.tryEval (builtins.deepSeq l.config.lab.out.cliConfig "evaluated")).success;

  results = lib.runTests {

    # The control. Without it every refusal below could pass because the
    # harness builds a lab that is broken for an unrelated reason — which is
    # how five refusals in `nix/checks/secret-sharing.nix` once passed while
    # checking nothing.
    testTheHarnessBuildsALabThatIsAccepted = {
      expr = refuses (mkEdgeLab {
        name = "edge-ok";
        cluster = c: c;
      });
      expected = false;
    };

    # A cluster that says the lab is its edge and then names no backend is a
    # contradiction, not an unsupported provisioner. Before the mode existed
    # this was the *only* thing a non-k3d cluster could be, so the refusal
    # read as "this provisioner is not supported" and the fix was to teach the
    # lab about it. Now there is a way to say "not mine", and this fires only
    # for a lab that declined to use it.
    testTheLabIsTheEdgeAndNamesNoBackend = {
      expr = refuses (mkEdgeLab {
        name = "edge-none";
        cluster = c: lib.recursiveUpdate c { edge.backend = lib.mkForce null; };
      });
      expected = true;
    };

    # And the pair that makes the refusal above about the *combination*
    # rather than about a null backend: the same null is fine the moment the
    # cluster stops claiming the lab fronts it. This is the arrangement a
    # managed cloud cluster is in, expressed on a k3d one because no cloud
    # provisioner floe is built yet.
    testANullBackendIsFineWhenTheLabIsNotTheEdge = {
      expr = refuses (mkEdgeLab {
        name = "edge-self";
        cluster =
          c:
          lib.recursiveUpdate c {
            edge.mode = lib.mkForce "self";
            edge.backend = lib.mkForce null;
          };
      });
      expected = false;
    };
  };
in
{
  lab-edge = pkgs.runCommand "lab-edge-tests" { } ''
    ${lib.optionalString (results != [ ]) ''
      echo 'lab-edge FAILED:' >&2
      echo ${lib.escapeShellArg (builtins.toJSON results)} >&2
      exit 1
    ''}
    touch $out
  '';
}
