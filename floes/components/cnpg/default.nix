# CloudNativePG: the operator that reconciles Postgres `Cluster` CRs.
#
# Only the operator. The old floe also declared `clusters.<name>` — Postgres
# instances of its own — which is a consumer's business and belongs on the
# floe that needs a database. It comes back when forgejo does.
{
  lib,
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "cnpg";
  summary = "CloudNativePG, the PostgreSQL operator.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.cnpg.chart}";
      defaultText = lib.literalExpression "cataCharts.cnpg.chart";
      description = "Store path of the CloudNativePG Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "cnpg-system";
      description = "Namespace the operator runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.postgresOperator = sigs.POSTGRES_OPERATOR;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.provides.postgresOperator = {
          crdKinds = [
            "postgresql.cnpg.io/Cluster"
            "postgresql.cnpg.io/Pooler"
            "postgresql.cnpg.io/ScheduledBackup"
            "postgresql.cnpg.io/Backup"
          ];
        };

        config.floe.out.component = kinds.mkComponent {
          backs.postgresOperator = [ "cnpg" ];
          imagesComplete = true;

          bundles.cnpg = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            crds = [
              "postgresql.cnpg.io/Cluster"
              "postgresql.cnpg.io/Pooler"
              "postgresql.cnpg.io/ScheduledBackup"
              "postgresql.cnpg.io/Backup"
            ];

            helmCharts.cnpg = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "cnpg";
              values = { };
            };

            images.operator = kinds.mkImage "ghcr.io/cloudnative-pg/cloudnative-pg:1.25.0";

            ready = kinds.readyDeployment {
              name = "cnpg-cloudnative-pg";
              namespace = inputs.namespace;
            };
          };
        };
      }
    )
  ];
}
