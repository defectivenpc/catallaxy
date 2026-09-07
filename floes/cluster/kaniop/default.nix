# Kaniop: the operator that reconciles Kanidm CRs.
#
# Two bundles because there are two readiness facts. The CRDs are established
# well before the controller is up, and a consumer applying a `Kanidm` needs
# the first while a consumer waiting for reconciliation needs the second.
{
  catallaxy,
  lib,
  pkgs,
  floe,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "kaniop";
  summary = "The kaniop operator, which reconciles Kanidm and its clients.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the kaniop Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kanidm";
      description = "Namespace the controller runs in.";
    };
  };

  provides.operator = sigs.IDENTITY_OPERATOR;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        crdsEstablished = "kaniop/crds/established";

        # The chart ships its CRDs as a file rather than as templates, so they
        # are lifted out at build time and installed as their own bundle. This
        # is why the floe takes `pkgs`: it is a derivation, not an input.
        crds = pkgs.runCommand "kaniop-crds" { } ''
          cp ${inputs.chart}/crds/crds.yaml $out
        '';
      in
      {
        config.floe.provides.operator = {
          inherit crdsEstablished;
        };

        config.floe.out.component = kinds.mkComponent {
          # Both, and in that order: a consumer of IDENTITY_OPERATOR wants the
          # kind to exist *and* something reconciling it.
          backs.operator = [
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
              inherit (inputs) chart namespace;
              releaseName = "kaniop";
              values = { };
            };

            images.operator = {
              registry = "ghcr.io";
              repository = "pando85/kaniop";
              tag = "0.11.1";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/kaniop";
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
