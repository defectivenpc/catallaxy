# OT-Container-Kit's Redis operator: reconciles Redis and RedisCluster CRs.
{
  lib,
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "redis-operator";
  summary = "OT-Container-Kit's Redis operator.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.redis-operator.chart}";
      defaultText = lib.literalExpression "cataCharts.redis-operator.chart";
      description = "Store path of the redis-operator Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "redis-operator";
      description = "Namespace the operator runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.redisOperator = sigs.REDIS_OPERATOR;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.redisOperator = {
          crdKinds = [
            "redis.redis.opstreelabs.in/Redis"
            "redis.redis.opstreelabs.in/RedisCluster"
          ];
        };

        config.floe.out.component = kinds.mkComponent {
          backs.redisOperator = [ "redis-operator" ];
          imagesComplete = true;

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

            images.operator = kinds.mkImage "ghcr.io/ot-container-kit/redis-operator/redis-operator:v0.18.0";

            ready = kinds.readyDeployment {
              name = "redis-operator";
              namespace = inputs.namespace;
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
