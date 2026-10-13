# Velero: backups of the cluster, into an object store.
#
# It takes its bucket endpoint from `OBJECT_STORE`
# rather than from a hostname written twice. An earlier design read
# seaweedfs's own options with a hardcoded fallback beside them,
# which is a default that silently works until the day the store moves.
#
# The seven `ops` commands are wrappers around the `velero` binary, which is
# why each is a `package` rather than a fixed argv: they take user arguments
# and need `velero` on PATH.
#
# An earlier design gave every one a required `--cluster` enum with exactly one
# value — `config.cluster.name` — that the script then ignored, baking the
# kubecontext in at build time regardless. That is not carried forward. The
# context this floe backs up is the one it `requires`, and it knows it; and
# the case the flag was standing in for — two clusters in a lab both running
# velero — is caught by `opsCollisions` in `modules/lab/out.nix`, which names
# both clusters rather than making every invocation carry a flag with one
# legal value.
{
  floe,
  cataCharts ? null,
  lib,
  pkgs,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "velero";
  summary = "Velero, cluster backup and restore against an object store.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.velero.chart}";
      defaultText = lib.literalExpression "cataCharts.velero.chart";
      description = "Store path of the Velero Helm chart. Required.";
    };

    crds = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.velero.crds}";
      defaultText = lib.literalExpression "cataCharts.velero.crds";
      description = ''
        Store path of the CRD manifest extracted from the chart. Required.

        Their own bundle, because a consumer emitting a `Backup` needs the
        kind to exist without waiting for the controller, and because the
        chart ships its CRDs in `crds/` — which `helm template` does not
        render, so nothing else here would apply them.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "velero";
      description = "Namespace the controller runs in.";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "velero";
      description = "Bucket backups are written to. It must already exist.";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "us-east-1";
      description = ''
        Region the S3 client claims.

        Meaningless to a self-hosted store and required by the client anyway:
        the AWS SDK refuses to sign a request without one.
      '';
    };

    schedules = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            schedule = lib.mkOption {
              type = lib.types.str;
              description = "Cron expression.";
            };
            ttl = lib.mkOption {
              type = lib.types.str;
              default = "168h";
              description = "How long a backup from this schedule is kept.";
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''{ daily = { schedule = "0 2 * * *"; ttl = "168h"; }; }'';
      description = "Recurring backups, as Velero `Schedule` resources.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.objectStore = sigs.OBJECT_STORE;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        store = config.floe.requires.objectStore;
        cluster = config.floe.requires.cluster;

        credentialsSecret = "velero-credentials";

        velero =
          name: text:
          "${
            pkgs.writeShellApplication {
              name = "velero-${name}";
              runtimeInputs = [
                pkgs.kubectl
                pkgs.velero
              ];
              text = ''
                KUBE_CONTEXT=${lib.escapeShellArg cluster.context}
                ${text}
              '';
            }
          }/bin/velero-${name}";

        storeIsOpen = store.credentials == null;
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          assertions = [
            {
              assertion = storeIsOpen;
              message =
                "the object store at '${store.s3Endpoint}' requires credentials, and velero's "
                + "AWS plugin reads them from a credentials *file* rather than from the two keys "
                + "the store publishes. Building that file means rendering the values into a "
                + "manifest, which puts them in the digest and in the Nix store. It needs a "
                + "projection or a generated Secret shaped like the file, which is not built yet.";
            }
          ];

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.crds ];
            crds = map (k: "velero.io/${k}") [
              "Backup"
              "BackupRepository"
              "BackupStorageLocation"
              "DeleteBackupRequest"
              "DownloadRequest"
              "PodVolumeBackup"
              "PodVolumeRestore"
              "Restore"
              "Schedule"
              "ServerStatusRequest"
              "VolumeSnapshotLocation"
            ];
            awaitRollout = false;
          };

          bundles.velero = kinds.mkBundle {
            needs = [ "crds" ];
            createNamespaces = [ inputs.namespace ];

            resources = {
              credentials = {
                apiVersion = "v1";
                kind = "Secret";
                metadata = {
                  name = credentialsSecret;
                  inherit (inputs) namespace;
                  labels."app.kubernetes.io/managed-by" = "catallaxy";
                };
                type = "Opaque";
                stringData.cloud = ''
                  [default]
                  aws_access_key_id = unauthenticated
                  aws_secret_access_key = unauthenticated
                '';
              };
            }
            // lib.mapAttrs' (
              name: s:
              lib.nameValuePair "schedule-${name}" {
                apiVersion = "velero.io/v1";
                kind = "Schedule";
                metadata = {
                  name = name;
                  inherit (inputs) namespace;
                };
                spec = {
                  inherit (s) schedule;
                  template = {
                    inherit (s) ttl;
                    excludedNamespaces = [
                      "kube-system"
                      inputs.namespace
                    ];
                    includeClusterResources = true;
                  };
                };
              }
            ) inputs.schedules;

            helmCharts.velero = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "velero";
              values = {
                upgradeCRDs = false;

                credentials = {
                  useSecret = true;
                  existingSecret = credentialsSecret;
                };

                configuration.backupStorageLocation = [
                  {
                    name = "default";
                    provider = "aws";
                    inherit (inputs) bucket;
                    config = {
                      inherit (inputs) region;

                      s3Url = store.s3Endpoint;

                      s3ForcePathStyle = "true";
                    };
                    credential = {
                      name = credentialsSecret;
                      key = "cloud";
                    };
                  }
                ];

                initContainers = [
                  {
                    name = "velero-plugin-for-aws";
                    image = "velero/velero-plugin-for-aws:v1.12.0";
                    imagePullPolicy = "IfNotPresent";
                    volumeMounts = [
                      {
                        mountPath = "/target";
                        name = "plugins";
                      }
                    ];
                  }
                ];

                snapshotsEnabled = false;
                deployNodeAgent = false;
              };
            };

            images.velero = kinds.mkImage "docker.io/velero/velero:v1.16.0";
            images.awsPlugin = kinds.mkImage "docker.io/velero/velero-plugin-for-aws:v1.12.0";

            ready = kinds.readyDeployment {
              name = "velero";
              namespace = inputs.namespace;
            };

            ops.backup = {
              create = kinds.mkOpsCommand {
                description = "Create a backup";
                args = [
                  {
                    name = "name";
                    description = "Backup name. Timestamped if omitted.";
                    required = false;
                  }
                ];
                package = velero "create" ''
                  # kube-system holds the cluster's own control plane and
                  # velero's namespace holds the backup records themselves;
                  # restoring either over a live cluster is how a restore
                  # takes down the thing it was meant to rescue.
                  velero backup create "''${1:-$(date +%Y%m%d-%H%M%S)}" \
                    --kubecontext "$KUBE_CONTEXT" \
                    --exclude-namespaces kube-system,${inputs.namespace} \
                    --include-cluster-resources=true \
                    --wait
                '';
              };

              list = kinds.mkOpsCommand {
                description = "List backups";
                package = velero "list" ''
                  velero backup get --kubecontext "$KUBE_CONTEXT"
                '';
              };

              describe = kinds.mkOpsCommand {
                description = "Describe a backup";
                args = [
                  {
                    name = "name";
                    description = "Backup name";
                  }
                ];
                package = velero "describe" ''
                  velero backup describe "$1" --kubecontext "$KUBE_CONTEXT" --details
                '';
              };

              delete = kinds.mkOpsCommand {
                description = "Delete a backup";
                args = [
                  {
                    name = "name";
                    description = "Backup name";
                  }
                ];
                package = velero "delete" ''
                  velero backup delete "$1" --kubecontext "$KUBE_CONTEXT" --confirm
                '';
              };

              restore = kinds.mkOpsCommand {
                description = "Restore from a backup";
                args = [
                  {
                    name = "backup";
                    description = "Backup to restore from";
                  }
                ];
                package = velero "restore" ''
                  velero restore create --from-backup "$1" --kubecontext "$KUBE_CONTEXT" --wait
                '';
              };

              schedules = kinds.mkOpsCommand {
                description = "List backup schedules";
                package = velero "schedules" ''
                  velero schedule get --kubecontext "$KUBE_CONTEXT"
                '';
              };

              trigger = kinds.mkOpsCommand {
                description = "Run a schedule now";
                args = [
                  {
                    name = "schedule";
                    description = "Schedule to trigger";
                  }
                ];
                package = velero "trigger" ''
                  velero backup create --from-schedule "$1" --kubecontext "$KUBE_CONTEXT"
                '';
              };
            };
          };
        };
      }
    )
  ];
}
