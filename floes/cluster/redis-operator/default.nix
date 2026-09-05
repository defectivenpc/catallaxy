# OT-Container-Kit's Redis operator: reconciles Redis and RedisCluster CRs.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "redis-operator";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the redis-operator Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "redis-operator";
      description = "Namespace the operator runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.operator = sigs.REDIS_OPERATOR;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.operator = {
          crdKinds = [
            "redis.redis.opstreelabs.in/Redis"
            "redis.redis.opstreelabs.in/RedisCluster"
          ];
        };

        config.floe.out.component = kinds.mkComponent {
          backs.operator = [ "redis-operator" ];
          imagesComplete = true;
          network.declared = true;

          bundles.redis-operator = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            crds = [
              "redis.redis.opstreelabs.in/Redis"
              "redis.redis.opstreelabs.in/RedisCluster"
            ];

            helmCharts.redis-operator = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "redis-operator";
              values = { };
            };

            images.operator = {
              registry = "ghcr.io";
              repository = "ot-container-kit/redis-operator/redis-operator";
              tag = "v0.18.0";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/redis-operator";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
