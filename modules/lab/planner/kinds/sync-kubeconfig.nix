{ lib }:

{
  directions = [ "deploy" ];
  idempotency = "idempotent";
  dialsLabEndpoints = false;
  dryRunSafe = false;
  params.options = {
    target = lib.mkOption {
      type = lib.types.str;
      description = "Cluster holding the kubeconfigs to read.";
    };
    clusters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Clusters whose kubeconfigs are written to the local kubeconfig.";
    };
    kubeContext = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
    };
    fromSecret = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            store = lib.mkOption {
              type = lib.types.str;
              description = "Secret store holding the kubeconfig.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              description = "Key inside that store.";
            };
          };
        }
      );
      default = null;
      description = ''
        Read the kubeconfig from a lab secret store instead of from a
        Crossplane connection Secret on `target`.

        The two camps produce a kubeconfig in different places and there is
        one step for both, because what the step *does* — write it locally
        under the context the lab decided — is the same either way. A
        state-based apply publishes its output into a store (RFC 0003 §7);
        a controller writes a connection Secret in the cluster it runs in.
      '';
    };
  };
}
