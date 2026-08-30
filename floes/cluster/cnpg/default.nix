# CloudNativePG: the operator that reconciles Postgres `Cluster` CRs.
#
# Only the operator. The old floe also declared `clusters.<name>` — Postgres
# instances of its own — which is a consumer's business and belongs on the
# floe that needs a database. It comes back when forgejo does.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "cnpg";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the CloudNativePG Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "cnpg-system";
      description = "Namespace the operator runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.operator = sigs.POSTGRES_OPERATOR;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        readyToken = "cnpg/operator/ready";
      in
      {
        config.floe.provides.operator = {
          inherit readyToken;
          crdKinds = [
            "postgresql.cnpg.io/Cluster"
            "postgresql.cnpg.io/Pooler"
            "postgresql.cnpg.io/ScheduledBackup"
            "postgresql.cnpg.io/Backup"
          ];
        };

        config.floe.out.component = kinds.mkComponent {
          backs.operator = [ "cnpg" ];
          imagesComplete = true;

          network = {
            declared = true;
            serves.webhook = {
              port = 9443;
              fromApiServer = true;
            };
          };

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

            images.operator = {
              registry = "ghcr.io";
              repository = "cloudnative-pg/cloudnative-pg";
              tag = "1.25.0";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/cnpg-cloudnative-pg";
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
