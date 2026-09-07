# Forgejo: git over HTTP, for a lab that wants to push somewhere it controls.
#
# 260 lines against the parked 1,233, and the same two reasons as harbor's:
# most of the parked file was option surface, and what stays is the secrets the
# chart would otherwise mint while rendering.
#
# It provides GIT_REPOSITORY, which is what makes a gitops lab possible without
# a repository outside the lab — Round 4's argocd clones from here.
{
  lib,
  pkgs,
  floe,
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
  requires.generation = sigs.SECRET_GENERATION;

  requiresOptional.oidc = sigs.OIDC_PROVIDER;

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
        idempotent = import ../../../lib/util/idempotent-job.nix { inherit lib; };

        # `extraData` for the username, the same shape grafana and harbor use:
        # a consumer cloning from here needs both, and a username is not a
        # secret.
        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = adminSecret;
          key = "password";
          length = 24;
          # Forgejo's admin password reaches its init job through an env var
          # that the chart's shell does not quote.
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

          # The chart's HTTP Service. No TLS on it: the certificate is on the
          # gateway, and an in-cluster client dialling this directly is
          # dialling past it.
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

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          network = {
            declared = true;
            serves.http = {
              port = 3000;
              protocol = "TCP";
              fromExternal = false;
              fromApiServer = false;
            };
            reaches = [ ];
          };

          backs.git = [ "forgejo" ];

          bundles.forgejo = kinds.mkBundle {
            createNamespaces = [ ns ];

            images.forgejo = {
              registry = "codeberg.org";
              repository = "forgejo/forgejo";
              # The chart's appVersion with the chart's own `-rootless`
              # suffix. `12.0.4` was a guess at a much newer Forgejo than this
              # chart pins.
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

                  # Explicit, because `mkRoute` defaults the hostname from
                  # `name` and this floe is called forgejo while it answers on
                  # `git.`. Left to the default it served `forgejo.<zone>` and
                  # every clone of `git.<zone>` got a 503 from the ingress —
                  # a route that exists and a host nothing serves.
                  hostname = host;
                };
              };

            inherit (admin) secrets;
            externalSecrets = lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.forgejo = {
              inherit (inputs) chart;
              releaseName = "forgejo";
              namespace = ns;
              values = {
                persistence = {
                  enabled = true;
                  size = inputs.storage;
                };

                # All off. A lab this size runs one Forgejo pod against
                # SQLite; the chart's defaults bring up an HA PostgreSQL and a
                # six-node Redis cluster to serve it. `redis-cluster` is the
                # one that is on by default, and the image gate is what found
                # it still rendering after the other two were turned off.
                "postgresql-ha".enabled = false;
                postgresql.enabled = false;
                "redis-cluster".enabled = false;

                gitea = {
                  admin = {
                    existingSecret = adminSecret;
                    # Left to the chart these are a literal username and a
                    # literal password in the rendered manifest — the same
                    # `randAlphaNum`-at-render-time problem as harbor's six.
                    passwordMode = "keepUpdated";
                  };

                  config = {
                    server = {
                      DOMAIN = host;
                      ROOT_URL = "https://${host}";
                      # The port inside the pod, not the routed one. The chart
                      # defaults it from `ROOT_URL`, which would have the
                      # server bind 443 and fail without a certificate.
                      HTTP_PORT = 3000;
                    };
                    database.DB_TYPE = "sqlite3";
                    service.DISABLE_REGISTRATION = true;
                  }
                  // lib.optionalAttrs inputs.oidc {
                    # Forgejo takes a login source through its CLI rather than
                    # its config, so this only turns the feature on; the source
                    # itself is added by `cata lab ops git add-login-source`.
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
              # A Deployment. Newer Forgejo charts use a StatefulSet and this
              # one does not — the ready-probe lint caught the assumption,
              # which would otherwise have waited out its timeout on a
              # workload that does not exist.
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

          # Its own bundle, because `cata`'s `bootstrap-forgejo-repos` step
          # waits on this Job by label and a bundle is what orders it after the
          # server. Wrapped in `mkIdempotentJob` so a re-render does not run it
          # again: creating a repository twice is a 409, and a Job that fails
          # on its second `lab up` fails the deploy.
          bundles.bootstrap = kinds.mkBundle {
            needs = [ "forgejo" ];

            images.bootstrap = {
              registry = "docker.io";
              repository = "curlimages/curl";
              tag = "8.11.1";
              digest = null;
            };

            resources =
              (idempotent.mkIdempotentJob {
                name = "forgejo-bootstrap";
                namespace = ns;

                # What it was asked to make. Not the image and not the script.
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

            # The label `cata` selects on. Set through the constructor's
            # `extraLabels` would be tidier; this Job's own component label is
            # already its name, which is what the step's default selector
            # matches.
            awaitRollout = false;
          };
        };
      }
    )
  ];
}
