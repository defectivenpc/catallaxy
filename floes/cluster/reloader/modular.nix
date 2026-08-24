# reloader, ported to the floe interface.
#
# Spike artefact: this is the same floe as ./default.nix written as an
# *instance* of the type in `lib/floe/interface.nix` rather than as a module
# that declares `options.floes.reloader`. Both exist so the two can be
# compared — `lib/tests/floe-port-equivalence.nix` evaluates them side by side
# and asserts they produce the same data.
#
# The differences, all of which are the point:
#
#   - no `floeOptions` call, no barrel import, no `cfg` binding: the interface
#     arrives with the type, and `config` *is* this floe;
#   - `bundles.reloader` rather than `floes.reloader.bundles.reloader`, on
#     every line of the body;
#   - `options.exports.<field>` rather than `options.floes.reloader.exports`,
#     extending the interface's `exports` submodule.
{
  config,
  lib,
  cataCharts,
  ...
}:

let
  inherit (lib) mkOption types;
  inherit ((import ../../../lib/floe { inherit lib; })) refs;

  secretReloadAnnotation = "secret.reloader.stakater.com/reload";
  configMapReloadAnnotation = "configmap.reloader.stakater.com/reload";
in
{
  options = {
    chart = mkOption {
      type = types.package;
      default = cataCharts.reloader.chart;
      description = "Helm chart to install. Defaults to the chart catallaxy pins.";
    };

    exports = mkOption {
      type = types.submodule {
        options = {
          watching = mkOption {
            type = refs.mkCapability {
              ready = refs.tokenOption ''"The reloader controller is watching and will roll annotated workloads."'';
            };
            default = null;
            description = ''
              Workload reload-on-rotation, or null when this floe is off.
              Consumers that annotate for reload gate on this rather than
              naming `reloader/watching` themselves.
            '';
          };

          secretReloadAnnotation = mkOption {
            type = types.str;
            default = secretReloadAnnotation;
            description = ''
              The pod-template annotation key reloader watches for Secret
              references. Value should be a comma-separated list of Secret
              names in the same namespace as the workload.
            '';
          };

          configMapReloadAnnotation = mkOption {
            type = types.str;
            default = configMapReloadAnnotation;
            description = ''
              The pod-template annotation key reloader watches for ConfigMap
              references. Value should be a comma-separated list of ConfigMap
              names in the same namespace as the workload.
            '';
          };

          mkPatches = mkOption {
            type = types.raw;
            default = _workloads: [ ];
            description = ''
              Kustomize strategic-merge patch constructor. Takes a list of
              workload references and returns patch entries suitable for a
              Helm chart's `kustomize.patches`. Signature:

                [ { kind :: "Deployment"|"StatefulSet"|"DaemonSet";
                    name :: str;
                    secrets ? [ str ];
                    configMaps ? [ str ]; } ]
                → [ kustomizePatchEntry ]

              Mirrors `lib/util/kapp.nix::mkPreserveRuntimePatches` so both
              compose in the same list.
            '';
          };
        };
      };
    };
  };

  config = lib.mkIf config.enable {
    exports = {
      watching.ready = "reloader/watching";
      inherit secretReloadAnnotation configMapReloadAnnotation;

      mkPatches =
        workloads:
        map (
          w:
          let
            annotations =
              lib.optionalAttrs (w.secrets or [ ] != [ ]) {
                ${secretReloadAnnotation} = lib.concatStringsSep "," w.secrets;
              }
              // lib.optionalAttrs (w.configMaps or [ ] != [ ]) {
                ${configMapReloadAnnotation} = lib.concatStringsSep "," w.configMaps;
              };
          in
          {
            target = { inherit (w) kind name; };
            patch = builtins.toJSON {
              apiVersion = "apps/v1";
              inherit (w) kind;
              metadata = {
                inherit (w) name;
                inherit annotations;
              };
            };
          }
        ) workloads;
    };

    network.declared = true;

    imagesComplete = true;

    images.controller = {
      registry = "ghcr.io";
      repository = "stakater/reloader";
      tag = "v1.4.19";
    };

    bundles.reloader = {
      owner = {
        bootstrap = "install-target";
        steady = "argocd";
      };

      includeInBootstrap = false;
      helmCharts.reloader = {
        chart = config.chart;
        releaseName = "reloader";
        namespace = config.namespace;
        values.reloader = {
          watchGlobally = true;
          reloadOnCreate = true;
        };
      };
      createNamespaces = [ config.namespace ];

      provides = [
        "reloader/watching"
        "config-reload/ready"
      ];
      readyProbe = {
        kind = "condition";
        resource = "deployment/reloader-reloader";
        namespace = config.namespace;
        condition = "Available";
        timeout = "3m";
      };
    };
  };
}
