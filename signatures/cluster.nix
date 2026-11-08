{ lib, floe }:

let
  T = floe.T;
in
{
  KUBERNETES_CLUSTER = floe.mkSig {
    name = "KUBERNETES_CLUSTER";
    canonicalName = "cluster";
    description = "The cluster a member installs into: its name, version, context and address ranges.";
    fields = {
      name = T.k8sName;
      version = T.str;
      context = T.str;
      podSubnet = T.str;
      serviceSubnet = T.str;

      assignsLoadBalancers = T.bool;
    };
  };

  CLUSTER_PROVISIONING = floe.mkSig {
    name = "CLUSTER_PROVISIONING";
    canonicalName = "provisioning";
    description = "An object in another cluster that reconciles into this one.";
    fields = {
      resourceKind = T.str;
      resourceName = T.k8sName;
    };
  };

  STORAGE_CLASS = floe.mkSig {
    name = "STORAGE_CLASS";
    canonicalName = "storageClass";
    description = "A StorageClass a PVC can name, and whether it is the cluster's default.";
    fields = {
      className = T.str;
      isDefault = T.bool;
    };
  };

  CNI_BOOTSTRAP = floe.mkSig {
    name = "CNI_BOOTSTRAP";
    canonicalName = "cniBootstrap";
    description = "A CNI's bootstrap manifest, applied by the provisioner before the first node is Ready.";
    fields = {
      name = T.k8sName;

      manifest = T.str;
    };
  };

  RESOURCE_OUTPUT = floe.mkSig {
    name = "catallaxy.resourceOutput";
    canonicalName = "resourceOutput";
    description = "Readable from a declared output of another resource, once that resource exists.";
    fields = {
      resource = T.str;
      output = T.str;
    };
  };

  DELIVERY_POLICY = floe.mkSig {
    name = "DELIVERY_POLICY";
    canonicalName = "delivery";
    description = "How manifests reach the cluster, what bootstraps the applier, and how long an apply may take.";
    fields = {
      strategy = T.enum [
        "kapp"
        "argocd"
        "fleet"
      ];
      bootstrapTool = T.enum [
        "kubectl-ssa"
        "helm"
        "none"
      ];

      waitTimeout = T.str;

      context = T.str;
    };
  };
}
