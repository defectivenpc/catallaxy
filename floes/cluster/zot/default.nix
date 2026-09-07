# Zot: an OCI registry inside the cluster.
#
# Distinct from `lab.registry`, which is a pull-through cache on the *host* in
# front of upstreams. This one holds images the lab itself produces, and lives
# in the cluster where the things that pull them are.
#
# Rebuilt against RFC 0001 rather than ported, and the values are written
# against the chart actually pinned (0.1.113) rather than carried over: the
# parked floe set `persistence = { enabled = true; size = ...; }`, and in this
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

  provides.registry = sigs.OCI_REGISTRY;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        # One binding, three projections: the URL something dials, the
        # reference an image carries, and the Service the chart names.
        host = "zot.${inputs.namespace}.svc.cluster.local";
        hostPort = "${host}:${toString inputs.port}";
      in
      {
        config.floe.provides.registry = {
          inherit (inputs) namespace;
          url = "http://${hostPort}";

          # No scheme. An image reference is not a URL, and a consumer that
          # has to strip one to make the other will eventually forget.
          pullRef = hostPort;

          # Open. Anything that can reach the Service can push, which is what
          # `network.serves` says and is only tolerable in a lab.
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
                # A boolean in this chart, not an object: true selects the
                # StatefulSet, false the Deployment. The claim is configured
                # separately, below.
                persistence = true;

                pvc = {
                  create = true;
                  accessModes = [ "ReadWriteOnce" ];
                  storage = inputs.storage;
                }
                // lib.optionalAttrs (inputs.storageClass != null) {
                  storageClassName = inputs.storageClass;
                };

                # The chart defaults to NodePort, which publishes the registry
                # on every node of the cluster. Nothing here wants that: the
                # lab reaches it through the gateway when it has a route, and
                # in-cluster consumers use the Service.
                service = {
                  type = "ClusterIP";
                  inherit (inputs) port;
                };
              };
            };

            images.zot = {
              registry = "ghcr.io";
              repository = "project-zot/zot";
              tag = "v2.1.16";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "statefulset/zot";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "5m";
            };
          };
        };
      }
    )
  ];
}
