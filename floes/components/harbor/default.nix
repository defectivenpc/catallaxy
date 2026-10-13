# Harbor: an OCI registry with projects, users and scanning.
#
# The input surface is deliberately four values rather than one per chart
# setting; a lab that needs more reaches the chart through `chart`.
#
# What it does not leave to the chart is the six secrets. Left to itself the chart mints them
# with `randAlphaNum` while rendering, so all six land in the manifest, in the
# digest that pins it and in the Nix store, and all six change on any
# re-render. That is not only a leak: a rotating `REGISTRY_HTTP_SECRET`
# invalidates every in-flight upload, and a rotating core secret breaks
# core↔jobservice until every pod has restarted. Each is minted in-cluster
# instead, at the length Harbor requires.
{
  lib,
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "harbor";
  summary = "Harbor, an OCI registry with its own database and cache.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.harbor.chart}";
      defaultText = lib.literalExpression "cataCharts.harbor.chart";
      description = "Store path of the Harbor Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "harbor";
      description = "Namespace Harbor runs in.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "10Gi";
      description = "Size of the volume the registry's blobs live on.";
    };

    oidc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register an OAuth2 client so Harbor can authenticate against the lab's
        issuer.

        Harbor's own OIDC settings are applied through its API rather than its
        chart, so this renders the client and lands the credentials; wiring
        them into Harbor's auth mode is a `cata lab ops` step, not a value.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # Claimed, so whatever answers for the zone learns this hostname from the
  # link rather than by reading what rendered. The gateway collects these.
  # ADR 0004.
  provides.route = sigs.ROUTE_CLAIM;

  # Six of them, and the reason is in the header.
  requires.generation = sigs.SECRET_GENERATION;

  # The token-signing CA. Left to itself the chart mints one per render.
  requires.issuance = sigs.X509_ISSUANCE;

  optional.oidc = sigs.OIDC_PROVIDER;

  provides.registry = sigs.OCI_REGISTRY;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;
        issuance = config.floe.requires.issuance;
        oidcProvider = config.floe.requires.oidc or null;

        host = "harbor.${gateway.baseDomain}";
        ns = inputs.namespace;

        gen =
          secret: key: length:
          kinds.mkGeneratedSecret {
            namespace = ns;
            inherit secret key length;
            symbols = 0;
          };

        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = "harbor-admin";
          key = "HARBOR_ADMIN_PASSWORD";
          length = 24;
          symbols = 0;
          extraData.harbor-user = "admin";
        };
        secretKey = gen "harbor-secret-key" "secretKey" 16;
        core = gen "harbor-core-secret" "secret" 16;
        xsrf = gen "harbor-xsrf" "CSRF_KEY" 32;
        jobservice = gen "harbor-jobservice-secret" "JOBSERVICE_SECRET" 16;
        registryHttp = gen "harbor-registry-http-secret" "REGISTRY_HTTP_SECRET" 16;

        registryUser = "harbor_registry_user";
        registryCredSecret = "harbor-registry-credential";
        registryCred = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = registryCredSecret;
          key = "REGISTRY_PASSWD";
          length = 24;
          symbols = 0;
          extraData.REGISTRY_HTPASSWD = ''{{ htpasswd "${registryUser}" .password }}'';
        };

        tokenSecret = "harbor-token-ca";

        generated = [
          admin
          registryCred
          secretKey
          core
          xsrf
          jobservice
          registryHttp
        ];

        client =
          if inputs.oidc && oidcProvider == null then
            throw ''
              harbor is configured to register an OAuth2 client, and nothing in
              this cluster provides OIDC_PROVIDER.

              Add an issuer, or set `oidc = false`.
            ''
          else
            lib.optionalAttrs inputs.oidc (
              kinds.mkOAuth2Client {
                provider = oidcProvider;
                name = "harbor";
                namespace = ns;
                origin = "https://${host}";
                redirectUrls = [ "https://${host}/c/oidc/callback" ];
              }
            );
      in
      {
        config.floe.provides.registry = {
          namespace = ns;
          url = "https://${host}";

          pullRef = host;

          credentials = {
            name = "harbor-admin";
            namespace = ns;
            usernameKey = "harbor-user";
            passwordKey = "HARBOR_ADMIN_PASSWORD";
          };
        };

        config.floe.provides.route.host = host;

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          backs.registry = [ "harbor" ];

          bundles.harbor = kinds.mkBundle {
            createNamespaces = [ ns ];

            images.core = kinds.mkImage "docker.io/goharbor/harbor-core:v2.15.1";
            images.portal = kinds.mkImage "docker.io/goharbor/harbor-portal:v2.15.1";
            images.jobservice = kinds.mkImage "docker.io/goharbor/harbor-jobservice:v2.15.1";
            images.registry = kinds.mkImage "docker.io/goharbor/registry-photon:v2.15.1";
            images.registryctl = kinds.mkImage "docker.io/goharbor/harbor-registryctl:v2.15.1";
            images.database = kinds.mkImage "docker.io/goharbor/harbor-db:v2.15.1";
            images.redis = kinds.mkImage "docker.io/goharbor/redis-photon:v2.15.1";
            images.nginx = kinds.mkImage "docker.io/goharbor/nginx-photon:v2.15.1";

            resources =
              lib.foldl' (acc: g: acc // g.resources) { } generated
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
                harbor-token = {
                  apiVersion = "cert-manager.io/v1";
                  kind = "Certificate";
                  metadata = {
                    name = "harbor-token";
                    namespace = ns;
                  };
                  spec = {
                    secretName = tokenSecret;
                    commonName = tokenSecret;
                    isCA = true;
                    privateKey = {
                      algorithm = "RSA";
                      size = 4096;
                    };
                    usages = [
                      "signing"
                      "key encipherment"
                      "cert sign"
                    ];
                    inherit (issuance) issuerRef;
                  };
                };
                harbor-route = kinds.mkRoute {
                  inherit gateway;
                  name = "harbor";
                  namespace = ns;
                  service = "harbor-nginx";
                  port = 80;
                };
              };

            secrets = lib.concatMap (g: g.secrets) generated;
            externalSecrets = [
              "${ns}/${tokenSecret}"
            ]
            ++ lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.harbor = kinds.mkHelmChart {
              inherit (inputs) chart;
              releaseName = "harbor";
              namespace = ns;
              values = {
                externalURL = "https://${host}";

                expose = {
                  type = "clusterIP";
                  tls.enabled = false;
                  clusterIP.name = "harbor-nginx";
                };

                persistence.persistentVolumeClaim.registry.size = inputs.storage;

                existingSecretAdminPassword = "harbor-admin";
                existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD";
                existingSecretSecretKey = "harbor-secret-key";

                core = {
                  existingSecret = "harbor-core-secret";
                  existingXsrfSecret = "harbor-xsrf";
                  existingXsrfSecretKey = "CSRF_KEY";
                  secretName = tokenSecret;
                };
                jobservice = {
                  existingSecret = "harbor-jobservice-secret";
                  existingSecretKey = "JOBSERVICE_SECRET";
                };
                registry = {
                  existingSecret = "harbor-registry-http-secret";
                  existingSecretKey = "REGISTRY_HTTP_SECRET";
                  credentials = {
                    username = registryUser;
                    existingSecret = registryCredSecret;
                  };
                };

                trivy.enabled = false;
              };
            };

            ready = kinds.readyDeployment {
              name = "harbor-core";
              namespace = ns;
              timeout = "10m";
            };
          };
        };
      }
    )
  ];
}
