{ lib }:

{
  "apply-root-application" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = true;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster whose argocd receives the root Application.";
      };
      namespace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Namespace argocd runs in.";
      };
      manifestPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the rendered root Application manifest, relative to the lab package.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "bootstrap-argocd-kubectl-ssa" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster argocd is installed on.";
      };
      manifestRoot = lib.mkOption {
        type = lib.types.str;
        description = "Directory of bootstrap manifests to apply, relative to the lab package.";
      };
      fieldManager = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Server-side-apply field manager to own the applied objects.";
      };
      namespace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Namespace to install argocd into.";
      };
      waitTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds to wait for the applied workloads to become ready.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "bootstrap-forgejo-repos" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = true;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster running the forgejo bootstrap Job.";
      };
      namespace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Namespace forgejo runs in.";
      };
      jobLabelSelector = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Label selector identifying the bootstrap Job to wait on.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "cert-generate" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      zone = lib.mkOption {
        type = lib.types.str;
        description = "DNS zone the wildcard ingress certificate is minted for.";
      };
    };
  };

  "create-cluster" = {
    directions = [ "deploy" ];
    idempotency = "oneShot";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Cluster to create.";
      };
      provisioner = lib.mkOption {
        type = lib.types.str;
        description = "Provisioner that creates it, as in `k3d` or `crossplane`.";
      };
    };
  };

  "delete-managed-resource" = {
    directions = [ "teardown" ];
    idempotency = "destructive";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster the managed resource represents.";
      };
      resourceKind = lib.mkOption {
        type = lib.types.str;
        description = "Fully qualified CRD kind of the managed resource.";
      };
      resourceName = lib.mkOption {
        type = lib.types.str;
        description = "Name of the managed resource to delete.";
      };
      wait = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Block until the resource is gone rather than returning once deletion is accepted.";
      };
      waitTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds to wait when `wait` is set.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context holding the managed resource, which is the provisioning cluster rather than the target.";
      };
      externalNameDiscoveryBin = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Executable that recovers the provider's external name before deletion.";
      };
    };
  };

  "deploy-manifests" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster whose rendered manifests are applied.";
      };
      bootstrap = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Apply the bootstrap-stage subset only, for a cluster that is not yet reachable at its final address.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "destroy-cluster" = {
    directions = [
      "deploy"
      "teardown"
    ];
    idempotency = "destructive";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Cluster to destroy.";
      };
      provisioner = lib.mkOption {
        type = lib.types.str;
        description = "Provisioner that owns it.";
      };
      skipIfMissing = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Succeed rather than fail when the cluster is already gone.";
      };
    };
  };

  "dns-setup" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Address of the lab's CoreDNS.";
      };
      port = lib.mkOption {
        type = lib.types.int;
        description = "Port the lab's CoreDNS listens on.";
      };
      zone = lib.mkOption {
        type = lib.types.str;
        description = "DNS zone to point at it.";
      };
    };
  };

  "dns-teardown" = {
    directions = [ "teardown" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      zone = lib.mkOption {
        type = lib.types.str;
        description = "DNS zone whose resolver configuration is removed from this machine.";
      };
    };
  };

  "docker-network-create" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Docker network to create.";
      };
      subnet = lib.mkOption {
        type = lib.types.str;
        description = "Subnet in CIDR form.";
      };
      gateway = lib.mkOption {
        type = lib.types.str;
        description = "Gateway address within the subnet.";
      };
    };
  };

  "ensure-secrets" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      stores = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Secret stores to generate and decrypt before the run begins.";
      };
    };
  };

  "infra-apply" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      stack = lib.mkOption {
        type = lib.types.str;
        description = "Stack this step acts on, which is one unit of state and one apply.";
      };
      workingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Directory the tool runs in. Null lets the CLI derive it, which is
          what a lab wants: it is host state, not something a lab declares.
        '';
      };
    };
  };

  "infra-destroy" = {
    directions = [ "teardown" ];
    idempotency = "destructive";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      stack = lib.mkOption {
        type = lib.types.str;
        description = "Stack this step acts on, which is one unit of state and one apply.";
      };
      workingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Directory the tool runs in. Null lets the CLI derive it, which is
          what a lab wants: it is host state, not something a lab declares.
        '';
      };
    };
  };

  "infra-plan" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      stack = lib.mkOption {
        type = lib.types.str;
        description = "Stack this step acts on, which is one unit of state and one apply.";
      };
      workingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Directory the tool runs in. Null lets the CLI derive it, which is
          what a lab wants: it is host state, not something a lab declares.
        '';
      };
    };
  };

  "publish-manifests" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = true;
    dryRunSafe = false;
    params.options = { };
  };

  "reconcile-managed-resource" = {
    directions = [ "teardown" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster the managed resource represents.";
      };
      resourceKind = lib.mkOption {
        type = lib.types.str;
        description = "Fully qualified CRD kind of the managed resource.";
      };
      resourceName = lib.mkOption {
        type = lib.types.str;
        description = "Name of the managed resource to adopt.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context holding the managed resource, which is the provisioning cluster rather than the target.";
      };
      externalNameDiscoveryBin = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Executable that recovers the provider's external name when the resource has lost it.";
      };
    };
  };

  "registry-setup" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      port = lib.mkOption {
        type = lib.types.int;
        description = "Port the lab registry listens on.";
      };
      zone = lib.mkOption {
        type = lib.types.str;
        description = "DNS zone the registry is reachable under.";
      };
      upstreams = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Upstream registry hosts to mirror.";
      };
    };
  };

  "release-cluster-cloud-resources" = {
    directions = [ "teardown" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster whose cloud LoadBalancers and Volumes are released.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
      waitTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds to wait for the cloud controllers to finish releasing.";
      };
    };
  };

  "remove-network" = {
    directions = [ "teardown" ];
    idempotency = "destructive";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = { };
  };

  "remove-services" = {
    directions = [ "teardown" ];
    idempotency = "destructive";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = { };
  };

  "run-script" = {
    directions = [
      "deploy"
      "teardown"
    ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = {
      bin = lib.mkOption {
        type = lib.types.str;
        description = ''
          Absolute path to the executable, in practice
          `"''${pkgs.writeShellApplication { ... }}/bin/<name>"`. The lab package
          symlinks it into `$out/hooks/` so Nix retains it as a real runtime
          dependency rather than a string-context ghost.
        '';
      };
      env = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Environment variable to set.";
              };
              secret = lib.mkOption {
                type = lib.types.str;
                description = ''
                  `lab.secrets.managed.<secret>` to read. The owning store is
                  resolved from that secret's own `store` attribute, the same
                  indirection `secrets.projections` uses via its `source` field,
                  so the two cannot drift.
                '';
              };
              key = lib.mkOption {
                type = lib.types.str;
                description = "Key within the managed secret.";
              };
            };
          }
        );
        default = [ ];
        description = ''
          Environment variables sourced from decrypted managed secrets and
          injected into the subprocess. The executor decrypts every declared
          store before the step loop begins, so a preflight can read a cloud
          credential before any cluster exists. A declared secret missing from
          the decrypted cache fails the step rather than running with the
          variable unset.
        '';
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context exported to the script. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "setup-services" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = { };
  };

  "sync-kubeconfig" = {
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

          Bundles and resources produce a kubeconfig in different places and there is
          one step for both, because what the step *does* — write it locally
          under the context the lab decided — is the same either way. A
          state-based apply publishes its output into a store;
          a controller writes a connection Secret in the cluster it runs in.
        '';
      };
    };
  };

  "wait-for-cluster-gone" = {
    directions = [ "teardown" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = true;
    params.options = {
      target = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cluster the managed resource represents.";
      };
      resourceKind = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Fully qualified CRD kind of the managed resource.";
      };
      resourceName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of the managed resource to wait on.";
      };
      waitTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds to wait for it to disappear.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context holding the managed resource.";
      };
    };
  };

  "wait-for-resources" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = true;
    params.options = {
      target = lib.mkOption {
        type = lib.types.str;
        description = "Cluster holding the resources to wait on.";
      };
      resources = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        default = [ ];
        description = "Resources to wait for, each an attrset of selector fields.";
      };
      waitTimeoutSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds to wait before the step fails.";
      };
      kubeContext = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Kube context the step's kubectl calls run against. Defaults to the scoped cluster's runtime context.";
      };
    };
  };

  "warm-cache" = {
    directions = [ "deploy" ];
    idempotency = "idempotent";
    dialsLabEndpoints = false;
    dryRunSafe = false;
    params.options = { };
  };
}
