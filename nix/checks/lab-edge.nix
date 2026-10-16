# Who fronts a cluster, from the lab's side.
#
# The fixture `examples/labs/tests/self-edge.nix` pins what a lab *with* a
# self-edge cluster renders. This pins the refusals, which have no fixture
# because a lab that is refused does not render.
#
# Two decisions meet here and they belong to different parties. Where a
# cluster is reachable is the provisioner's: every backend is built from the
# container-naming convention of the tool that created the cluster, and a
# cluster nobody here created answers nothing. Whether this lab fronts it is
# the deployer's, said by whether the cluster exports its `HOST_EXPOSURE`.
#
# So the refusal is about the *combination*, and it has to be: a cluster with
# no address is the ordinary case for a managed one, and asking a lab to route
# to it is the mistake.
{
  lib,
  pkgs,
  mkLab,
  catallaxy,
  floes,
}:

let
  # Two clusters would need two subnets and there is only one arrangement
  # under test, so one cluster and one set of ports throughout.
  mkEdgeLab =
    {
      name,
      provisioner,
      fronted ? true,
    }:
    mkLab (
      catallaxy.mkLabFloe
        {
          inherit name;
          summary = "A lab fronting one cluster, or declining to.";

          units = _: {
            proxy = floes.lab-proxy { httpPort = 8091; };

            declared = floes.lab-secret-store { backend = "env"; };
          };

          clusters = _: {
            app = {
              floe = catallaxy.mkClusterFloe {
                name = "lab-edge-app";
                summary = "A routed workload behind a gateway, for pinning who fronts a cluster.";

                requires = {
                  cluster = catallaxy.sigs.KUBERNETES_CLUSTER;
                  zone = catallaxy.sigs.DNS_ZONE;
                };

                optional = lib.optionalAttrs fronted { edge = catallaxy.sigs.CLUSTER_EDGE; };

                provides = {
                  delivery = catallaxy.sigs.DELIVERY_POLICY;
                }
                // lib.optionalAttrs fronted { exposure = catallaxy.sigs.HOST_EXPOSURE; };

                exports = {
                  delivery = "kapp/delivery";
                }
                // lib.optionalAttrs fronted { exposure = "gateway/exposure"; };

                units = _: {
                  kapp = floes.kapp { };
                  gateway-api = floes.gateway-api-crds { };
                  cert-manager = floes.cert-manager { };
                  gateway = floes.gateway { };
                  podinfo = floes.podinfo { };
                };
              } { };

              provisioner = provisioner floes;
            };
          };
        }
        {
          inherit name;
          zone = "${name}.test";
          subnet = "172.41.0.0/16";

          zonePort = 5371;

          defaults.LAB_SECRET_STORE = "declared";
        }
    );

  # Created here, so there is a container to name.
  k3dProvisioner = floes: floes.k3d-cluster { };

  # Created by someone else, so there is not. Everything about it is declared
  # because nothing in the lab made it.
  externalProvisioner =
    floes:
    floes.external-cluster {
      context = "external-app";
      podSubnet = "10.244.0.0/16";
      serviceSubnet = "10.96.0.0/12";
      kubeconfigKey = "clusters/app/kubeconfig";
    };

  refuses = l: !(builtins.tryEval (builtins.deepSeq l.cliConfig "evaluated")).success;

  results = lib.runTests {

    testTheHarnessBuildsALabThatIsAccepted = {
      expr = refuses (mkEdgeLab {
        name = "edge-ok";
        provisioner = k3dProvisioner;
      });
      expected = false;
    };

    testFrontingAClusterWithNoAddressIsRefused = {
      expr = refuses (mkEdgeLab {
        name = "edge-none";
        provisioner = externalProvisioner;
      });
      expected = true;
    };

    testTheSameClusterIsFineUnfronted = {
      expr = refuses (mkEdgeLab {
        name = "edge-self";
        provisioner = externalProvisioner;
        fronted = false;
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
