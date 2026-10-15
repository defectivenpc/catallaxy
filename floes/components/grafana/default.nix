# Grafana: dashboards over whatever the cluster stores.
#
# Four optional dependencies — metrics, logs, traces and OIDC — and a
# datasource exists exactly when its backend does. Neither the lab nor this
# floe says which are present anywhere: there is no `enable` to read, no URL
# to override and no assertion to keep in step.
#
# OIDC was once six consumers indexing a client registry by an id each
# had invented. Grafana registers its own client with `kinds.mkOAuth2Client`
# and reads the credentials from the Secret kaniop writes beside it.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "grafana";
  summary = "Grafana, wired to whichever metrics, logs and traces backends the cluster has.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the Grafana Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "monitoring";
      description = "Namespace Grafana runs in.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "2Gi";
      description = "Size of the volume dashboards and settings live on.";
    };

    oidc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Log in through the lab's OIDC issuer.

        Off by default: with nothing providing OIDC_PROVIDER this is refused
        rather than silently falling back to the admin password, and most labs
        that run Grafana do not run an issuer.
      '';
    };

    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Skip the login form and go straight to the issuer.

        Also disables the form, so a lab that turns this on and then loses its
        issuer has no way in at all. Off by default for that reason.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Somewhere for this floe's PersistentVolumeClaim to bind. Declared rather
  # than assumed: a PVC naming no class takes the cluster's default, and a
  # cluster with no default leaves it Pending forever with nothing in the
  # rendered output to say why. The claim answers it when the provisioner ships
  # one, and a storage floe in the cluster answers it otherwise.
  requires.storageClass = sigs.STORAGE_CLASS;
  requires.gateway = sigs.API_GATEWAY;

  # Claimed, so whatever answers for the zone learns this hostname from the
  # link rather than by reading what rendered. The gateway collects these.
  # ADR 0004.
  provides.route = sigs.ROUTE_CLAIM;

  # For the admin password. Left to the chart, it mints one while rendering —
  # so the value lands in the manifest, in the digest that pins it and in the
  # Nix store, and it changes on every re-render. `secret-material` refuses
  # exactly that, and caught this floe doing it.
  requires.generation = sigs.SECRET_GENERATION;

  # Zero or one of each. A datasource exists exactly when its backend does.
  optional.metrics = sigs.METRICS_INGEST;
  optional.logs = sigs.LOG_INGEST;
  optional.traces = sigs.TRACE_INGEST;
  optional.oidc = sigs.OIDC_PROVIDER;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;

        opt = hole: config.floe.requires.${hole} or null;

        metrics = opt "metrics";
        logs = opt "logs";
        traces = opt "traces";
        oidcProvider = opt "oidc";

        host = "grafana.${gateway.baseDomain}";

        adminSecret = "grafana-admin";

        admin = kinds.mkGeneratedSecret {
          inherit (inputs) namespace;
          secret = adminSecret;
          key = "admin-password";
          extraData.admin-user = "admin";
          symbols = 0;
        };

        client =
          if inputs.oidc && oidcProvider == null then
            throw ''
              grafana is configured to log in through OIDC, and nothing in this
              cluster provides OIDC_PROVIDER.

              Add an issuer, or set `oidc = false`.
            ''
          else
            lib.optionalAttrs inputs.oidc (
              kinds.mkOAuth2Client {
                provider = oidcProvider;
                name = "grafana";
                inherit (inputs) namespace;
                origin = "https://${host}";
                redirectUrls = [ "https://${host}/login/generic_oauth" ];
              }
            );

        datasources =
          lib.optional (metrics != null) {
            name = "Prometheus";
            type = "prometheus";
            url = metrics.queryUrl;
            isDefault = true;
            access = "proxy";
          }
          ++ lib.optional (logs != null) {
            name = "Loki";
            type = "loki";
            url = logs.queryUrl;
            access = "proxy";
          }
          ++ lib.optional (traces != null) {
            name = "Tempo";
            type = "tempo";
            url = traces.queryUrl;
            access = "proxy";
          };

        oidcSettings = lib.optionalAttrs inputs.oidc {
          "auth.generic_oauth" = {
            enabled = true;
            name = "Kanidm";
            allow_sign_up = true;
            auto_login = inputs.autoLogin;
            client_id = "\${__env{GF_OAUTH_CLIENT_ID}}";
            client_secret = "\${__env{GF_OAUTH_CLIENT_SECRET}}";
            scopes = "openid profile email groups";
            auth_url = "${oidcProvider.issuer}/ui/oauth2";
            token_url = "${oidcProvider.issuer}/oauth2/token";

            api_url = "${oidcProvider.issuer}/oauth2/openid/\${__env{GF_OAUTH_CLIENT_ID}}/userinfo";

            use_id_token = true;
            groups_attribute_path = "groups";
            role_attribute_path = "contains(groups[*], 'grafana_admins') && 'Admin' || 'Viewer'";
            skip_org_role_sync = false;
            use_pkce = true;
          };

          auth = {
            disable_login_form = inputs.autoLogin;
            oauth_auto_login = inputs.autoLogin;
          };
        };
      in
      {
        config.floe.provides.route.host = host;

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.grafana = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.grafana = {
              registry = "docker.io";
              repository = "grafana/grafana";
              tag = "12.3.1";
              digest = null;
            };

            images.init = kinds.mkImage "docker.io/library/busybox:1.31.1";

            resources =
              admin.resources
              // lib.optionalAttrs (client != { }) {
                oauth2-client = client.resource;
              }
              // {
                grafana-route = kinds.mkRoute {
                  inherit gateway;
                  name = "grafana";
                  inherit (inputs) namespace;
                  service = "grafana";
                  port = 80;
                };
              };

            inherit (admin) secrets;

            externalSecrets = lib.optional (client != { }) "${inputs.namespace}/${client.secret.name}";

            helmCharts.grafana = kinds.mkHelmChart {
              inherit (inputs) chart;
              releaseName = "grafana";
              namespace = inputs.namespace;
              values = {
                persistence = {
                  enabled = true;
                  size = inputs.storage;
                };

                admin = {
                  existingSecret = adminSecret;
                  userKey = "admin-user";
                  passwordKey = "admin-password";
                };

                "grafana.ini" = oidcSettings;

                datasources."datasources.yaml" = lib.optionalAttrs (datasources != [ ]) {
                  apiVersion = 1;
                  inherit datasources;
                };

                envValueFrom = lib.optionalAttrs (client != { }) {
                  GF_OAUTH_CLIENT_ID.secretKeyRef = {
                    name = client.secret.name;
                    key = client.secret.idKey;
                  };
                  GF_OAUTH_CLIENT_SECRET.secretKeyRef = {
                    name = client.secret.name;
                    key = client.secret.secretKey;
                  };
                };
              };
            };

            ready = kinds.readyDeployment {
              name = "grafana";
              namespace = inputs.namespace;
            };
          };

          assertions = [
            {
              assertion = datasources != [ ];
              message =
                "no METRICS_INGEST, LOG_INGEST or TRACE_INGEST is provided in this cluster, so "
                + "Grafana would come up with no datasource to query";
            }
          ];
        };
      }
    )
  ];
}
