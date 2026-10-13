# Forgejo: git over HTTP, for a lab that wants to push somewhere it controls.
#
# Same shape as harbor: a small input surface, and the secrets minted here
# rather than left to the chart, which would otherwise generate them while
# rendering and put them in the manifest.
#
# It provides GIT_REPOSITORY, which is what makes a gitops lab possible with no
# repository outside the lab — argocd clones from here.
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
  name = "forgejo";
  summary = "Forgejo, a git server, with an admin account and repositories bootstrapped.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.forgejo.chart}";
      defaultText = lib.literalExpression "cataCharts.forgejo.chart";
      description = "Store path of the Forgejo Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "forgejo";
      description = "Namespace Forgejo runs in.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "5Gi";
      description = "Size of the volume repositories live on.";
    };

    adminUser = lib.mkOption {
      type = lib.types.str;
      default = "forgejo-admin";
      description = ''
        Name of the initial admin account.

        Not `admin`: Forgejo reserves that name and refuses to create it,
        failing the chart's init job with a message about a reserved username
        rather than about the value you set.
      '';
    };

    oidc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add the lab's issuer as a login source.";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "lab";
      description = ''
        Repository the bootstrap Job creates for a CD tool to clone.

        `cata`'s `bootstrap-forgejo-repos` step waits for that Job by label,
        so a lab publishing manifests here needs it to exist and to finish.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # Claimed, so whatever answers for the zone learns this hostname from the
  # link rather than by reading what rendered. The gateway collects these.
  # ADR 0004.
  provides.route = sigs.ROUTE_CLAIM;
  requires.generation = sigs.SECRET_GENERATION;

  optional.oidc = sigs.OIDC_PROVIDER;

  provides.git = sigs.GIT_REPOSITORY;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;
        oidcProvider = config.floe.requires.oidc or null;

        ns = inputs.namespace;
        host = "git.${gateway.baseDomain}";

        adminSecret = "forgejo-admin";
        idempotent = import ../../../lib/kubernetes/idempotent-job.nix { inherit lib; };

        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = adminSecret;
          key = "password";
          length = 24;
          symbols = 0;
          extraData.username = inputs.adminUser;
        };

        client =
          if inputs.oidc && oidcProvider == null then
            throw ''
              forgejo is configured to use OIDC, and nothing in this cluster
              provides OIDC_PROVIDER.

              Add an issuer, or set `oidc = false`.
            ''
          else
            lib.optionalAttrs inputs.oidc (
              kinds.mkOAuth2Client {
                provider = oidcProvider;
                name = "forgejo";
                namespace = ns;
                origin = "https://${host}";
                redirectUrls = [ "https://${host}/user/oauth2/kanidm/callback" ];
              }
            );
      in
      {
        config.floe.provides.git = {

          internalUrl = "http://forgejo-http.${ns}.svc.cluster.local:3000";
          externalUrl = "https://${host}";
          cloneUrl = "https://${host}/${inputs.adminUser}/${inputs.repository}.git";

          credentials = {
            name = adminSecret;
            namespace = ns;
            username = inputs.adminUser;
            usernameKey = "username";
            passwordKey = "password";
          };
        };

        config.floe.provides.route.host = host;

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          backs.git = [ "forgejo" ];

          bundles.forgejo = kinds.mkBundle {
            createNamespaces = [ ns ];

            images.forgejo = {
              registry = "codeberg.org";
              repository = "forgejo/forgejo";
              tag = "1.21.11-1-rootless";
              digest = null;
            };

            resources =
              admin.resources
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
                forgejo-route = kinds.mkRoute {
                  inherit gateway;
                  name = "forgejo";
                  namespace = ns;
                  service = "forgejo-http";
                  port = 3000;

                  hostname = host;
                };
              };

            inherit (admin) secrets;
            externalSecrets = lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.forgejo = kinds.mkHelmChart {
              inherit (inputs) chart;
              releaseName = "forgejo";
              namespace = ns;
              values = {
                persistence = {
                  enabled = true;
                  size = inputs.storage;
                };

                "postgresql-ha".enabled = false;
                postgresql.enabled = false;
                "redis-cluster".enabled = false;

                gitea = {
                  admin.existingSecret = adminSecret;

                  config = {
                    server = {
                      DOMAIN = host;
                      ROOT_URL = "https://${host}";
                      HTTP_PORT = 3000;
                    };
                    database.DB_TYPE = "sqlite3";
                    service.DISABLE_REGISTRATION = true;
                  }
                  // lib.optionalAttrs inputs.oidc {
                    oauth2_client = {
                      ENABLE_AUTO_REGISTRATION = true;
                      ACCOUNT_LINKING = "auto";
                    };
                  };
                };
              };
            };

            ready = {
              kind = "condition";
              resource = "deployment/forgejo";
              namespace = ns;
              condition = "Available";
              timeout = "10m";
            };

            ops.git = {
              add-login-source = kinds.mkOpsCommand {
                description = "Register the lab's OIDC issuer as a Forgejo login source";
                command = [
                  "kubectl"
                  "-n"
                  ns
                  "exec"
                  "deploy/forgejo"
                  "--"
                  "forgejo"
                  "admin"
                  "auth"
                  "add-oauth"
                ];
              };
            };
          };

          bundles.bootstrap = kinds.mkBundle {
            needs = [ "forgejo" ];

            images.bootstrap = kinds.mkImage "docker.io/curlimages/curl:8.11.1";

            resources =
              (idempotent.mkIdempotentJob {
                name = "forgejo-bootstrap";
                namespace = ns;

                contentInputs = {
                  inherit (inputs) repository adminUser;
                };

                podSpec = {
                  restartPolicy = "OnFailure";
                  containers = [
                    {
                      name = "bootstrap";
                      image = "docker.io/curlimages/curl:8.11.1";
                      command = [
                        "sh"
                        "-c"
                      ];
                      args = [ (builtins.readFile ./scripts/bootstrap.sh) ];
                      env = [
                        {
                          name = "API";
                          value = "http://forgejo-http.${ns}.svc.cluster.local:3000";
                        }
                        {
                          name = "REPO";
                          value = inputs.repository;
                        }
                        {
                          name = "USERNAME";
                          valueFrom.secretKeyRef = {
                            name = adminSecret;
                            key = "username";
                          };
                        }
                        {
                          name = "PASSWORD";
                          valueFrom.secretKeyRef = {
                            name = adminSecret;
                            key = "password";
                          };
                        }
                      ];
                    }
                  ];
                };
              }).resources
              // { };

            awaitRollout = false;
          };
        };
      }
    )
  ];
}
