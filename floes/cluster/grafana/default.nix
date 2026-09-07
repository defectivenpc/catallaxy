# Grafana: dashboards over whatever the cluster stores.
#
# Two optional dependencies, both `requiresOptional`, and between them they
# are why this floe is 250 lines against the parked 615.
#
# The datasources were three `enable` reads into sibling floes' config, three
# URL options to override them, and an assertion apiece. A datasource now
# exists exactly when its backend does, and neither the lab nor this floe says
# so anywhere.
#
# OIDC was six consumers indexing `kanidm.exports.oauth2Clients` by an id each
# had invented. Grafana registers its own client with `kinds.mkOAuth2Client`
# and reads the credentials from the Secret kaniop writes beside it.
{
  lib,
  floe,
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
  requires.gateway = sigs.API_GATEWAY;

  # For the admin password. Left to the chart, it mints one while rendering —
  # so the value lands in the manifest, in the digest that pins it and in the
  # Nix store, and it changes on every re-render. `secret-material` refuses
  # exactly that, and caught this floe doing it.
  requires.generation = sigs.SECRET_GENERATION;

  # Zero or one of each. A datasource exists exactly when its backend does.
  requiresOptional.metrics = sigs.METRICS_INGEST;
  requiresOptional.logs = sigs.LOG_INGEST;
  requiresOptional.traces = sigs.TRACE_INGEST;
  requiresOptional.oidc = sigs.OIDC_PROVIDER;

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

        # Minted by external-secrets at apply time, so nothing is in the
        # rendered manifest. `extraData` carries the username beside it,
        # because the chart wants both keys from one Secret and a username is
        # not a secret — which is the case this constructor's `extraData` was
        # written for.
        admin = kinds.mkGeneratedSecret {
          inherit (inputs) namespace;
          secret = adminSecret;
          key = "admin-password";
          extraData.admin-user = "admin";
          # Grafana's own login form posts it; a symbol set that includes
          # quotes has no upside here and a history of breaking config readers.
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
                # Grafana's own callback path, which is not the default one.
                redirectUrls = [ "https://${host}/login/generic_oauth" ];
              }
            );

        # One entry per backend that resolved. Prometheus is default when it
        # is there, because a dashboard with no default datasource opens on an
        # error rather than on a panel.
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

        # The client id is not known at eval — kaniop mints it — so both
        # values arrive as environment variables from the Secret and the
        # config interpolates them. Grafana expands `$__env{}` in its own ini.
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

            # Per client, which is why the id has to be in the path and why
            # this cannot be built from the issuer alone.
            api_url = "${oidcProvider.issuer}/oauth2/openid/\${__env{GF_OAUTH_CLIENT_ID}}/userinfo";

            use_id_token = true;
            groups_attribute_path = "groups";
            role_attribute_path = "contains(groups[*], 'grafana_admins') && 'Admin' || 'Viewer'";
            skip_org_role_sync = false;
            use_pkce = true;
          };

          auth = {
            # Both, together. Hiding the form without disabling it leaves the
            # admin password reachable by anyone who knows the URL.
            disable_login_form = inputs.autoLogin;
            oauth_auto_login = inputs.autoLogin;
          };
        };
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.grafana = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.grafana = {
              registry = "docker.io";
              repository = "grafana/grafana";
              # The chart appVersion, not a guess: 12.1.1 was, and the gate
              # caught it.
              tag = "12.3.1";
              digest = null;
            };

            # The chart's init container, which chowns the data volume before
            # Grafana starts. Not optional and not obvious from the values —
            # the image gate found it.
            images.init = {
              registry = "docker.io";
              repository = "library/busybox";
              tag = "1.31.1";
              digest = null;
            };

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

            # The admin password, whose ExternalSecret is a resource in this
            # bundle. `secrets` is for what this bundle's own manifests cause.
            inherit (admin) secrets;

            # The client credentials are neither caused here nor missing.
            # kaniop mints them in response to the CR above, and kaniop belongs
            # to another floe — so nothing in the manifest stream creates them
            # and nothing should go looking for a creator. That is what
            # `externalSecrets` is for, and it is also what stops `cata lab
            # lint` calling the Deployment's reference to them dangling.
            externalSecrets = lib.optional (client != { }) "${inputs.namespace}/${client.secret.name}";

            helmCharts.grafana = {
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

            # The Deployment, not the ExternalSecret. The pod cannot start
            # without the generated Secret, so `awaitRollout` already blocks
            # until external-secrets has written it — and what a consumer of
            # Grafana cares about is Grafana answering, not a Secret existing.
            ready = {
              kind = "condition";
              resource = "deployment/grafana";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "5m";
            };
          };

          assertions = [
            {
              # A Grafana with no datasource is a login page over an empty
              # list. It renders, it is healthy, and it shows nothing.
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
