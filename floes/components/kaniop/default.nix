# Kaniop: the operator that reconciles Kanidm CRs.
#
# Two bundles because there are two readiness facts. The CRDs are established
# well before the controller is up, and a consumer applying a `Kanidm` needs
# the first while a consumer waiting for reconciliation needs the second.
{
  floe,
  upstream ? null,
  lib,
  pkgs,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "kaniop";
  summary = "The kaniop operator, which reconciles Kanidm and its clients.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the kaniop Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kanidm";
      description = "Namespace the controller runs in.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.identityOperator = sigs.IDENTITY_OPERATOR;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        crdsEstablished = "kaniop/crds/established";

        crds = pkgs.runCommand "kaniop-crds" { } ''
          cp ${inputs.chart}/crds/crds.yaml $out
        '';
      in
      {
        config.floe.provides.identityOperator = {
          inherit crdsEstablished;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.identityOperator = [
            "crds"
            "kaniop"
          ];
          imagesComplete = true;

          bundles.crds = kinds.mkBundle {
            yamls = [ "${crds}" ];
            crds = [
              "kaniop.rs/Kanidm"
              "kaniop.rs/KanidmPersonAccount"
              "kaniop.rs/KanidmGroup"
              "kaniop.rs/KanidmOAuth2Client"
              "kaniop.rs/KanidmServiceAccount"
            ];
          };

          bundles.kaniop = kinds.mkBundle {
            needs = [ "crds" ];
            createNamespaces = [ inputs.namespace ];

            helmCharts.kaniop = kinds.mkHelmChart {
              replacedHooks = {
                kaniop-crd-migrate = "the floe installs the CRDs itself, from the chart's own `crds/`, in `bundles.crds`";
                kaniop-crd-migrator = "as above";
                kaniop-crd-verify = "as above; `crdsEstablished` is what consumers wait on";
              };
              inherit (inputs) chart namespace;
              releaseName = "kaniop";
              values = { };
            };

            images.operator = kinds.mkImage "ghcr.io/pando85/kaniop:0.11.1";

            ready = kinds.readyDeployment {
              name = "kaniop";
              namespace = inputs.namespace;
            };
          };
        };
      }
    )
  ];
}
