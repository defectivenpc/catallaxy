# Zot: an OCI registry inside the cluster.
#
# Distinct from `lab.registry`, which is a pull-through cache on the *host* in
# front of upstreams. This one holds images the lab itself produces, and lives
# in the cluster where the things that pull them are.
#
# The values are written
# against the chart actually pinned (0.1.113) rather than carried over: the
# obvious spelling is `persistence = { enabled = true; size = ...; }`, and in this
# version `persistence` is a plain boolean selecting StatefulSet over
# Deployment, with the claim configured under `pvc`. The old shape is truthy,
# so it would have picked the right workload and silently ignored the size.
#
# No route and no auth in this round. Every lab that enabled it used only
# `enable`, an exactly-one `requires` on the gateway would force one on any
# lab that wants a registry, and OIDC waits for the identity work.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "zot";
  summary = "Zot, a small OCI registry used as the lab's pull-through cache.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the zot Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "zot";
      description = "Namespace it runs in.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port the registry serves on.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "8Gi";
      description = "Size of the volume claim holding the images.";
    };

    storageClass = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Storage class for that claim. Null takes the cluster's default.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Somewhere for this floe's PersistentVolumeClaim to bind. Declared rather
  # than assumed: a PVC naming no class takes the cluster's default, and a
  # cluster with no default leaves it Pending forever with nothing in the
  # rendered output to say why. The claim answers it when the provisioner ships
  # one, and a storage floe in the cluster answers it otherwise.
  requires.storageClass = sigs.STORAGE_CLASS;
  provides.registry = sigs.OCI_REGISTRY;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        host = "zot.${inputs.namespace}.svc.cluster.local";
        hostPort = "${host}:${toString inputs.port}";
      in
      {
        config.floe.provides.registry = {
          inherit (inputs) namespace;
          url = "http://${hostPort}";

          pullRef = hostPort;

          credentials = null;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.registry = [ "zot" ];
          imagesComplete = true;

          bundles.zot = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            helmCharts.zot = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "zot";
              values = {
                persistence = true;

                pvc = {
                  create = true;
                  accessModes = [ "ReadWriteOnce" ];
                  storage = inputs.storage;
                }
                // lib.optionalAttrs (inputs.storageClass != null) {
                  storageClassName = inputs.storageClass;
                };

                service = {
                  type = "ClusterIP";
                  inherit (inputs) port;
                };
              };
            };

            images.zot = kinds.mkImage "ghcr.io/project-zot/zot:v2.1.16";

            ready = kinds.readyCondition {
              resource = "statefulset/zot";
              condition = "Available";
              namespace = inputs.namespace;
            };
          };
        };
      }
    )
  ];
}
