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
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "harbor";
  summary = "Harbor, an OCI registry with its own database and cache.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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

  requires.gateway = sigs.API_GATEWAY;

  # Six of them, and the reason is in the header.
  requires.generation = sigs.SECRET_GENERATION;

  # The token-signing CA. Left to itself the chart mints one per render.
  requires.issuance = sigs.X509_ISSUANCE;

  requiresOptional.oidc = sigs.OIDC_PROVIDER;

  provides.registry = sigs.OCI_REGISTRY;

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

        # Every length here is Harbor's requirement, not a preference.
        # `secretKey` is the one that fails loudest: Harbor uses it as an AES
        # key and refuses to start on anything but exactly 16 characters.
        gen =
          secret: key: length:
          kinds.mkGeneratedSecret {
            namespace = ns;
            inherit secret key length;
            # No symbols anywhere. Several of these are read out of env vars by
            # Go code that does not quote them, and the chart puts two into a
            # connection string.
            symbols = 0;
          };

        # `extraData` carries the username, because a consumer pulling from
        # this registry needs both and a username is not a secret.
        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = "harbor-admin";
          key = "HARBOR_ADMIN_PASSWORD";
          length = 24;
          symbols = 0;
          extraData.harbor-user = "admin";
        };
        # Three of these are named `harbor-<component>-secret` rather than
        # `harbor-<component>`, and the suffix is load-bearing. The chart
        # renders its own Secrets called `harbor-core`, `harbor-jobservice`
        # and `harbor-registry`, carrying keys that have nothing to do with
        # the ones here — `POSTGRESQL_PASSWORD` and
        # `REGISTRY_CREDENTIAL_PASSWORD` among them. An ExternalSecret
        # targeting one of those names takes ownership of it and rewrites its
        # contents to just the generated key, so the chart's keys are silently
        # deleted after the apply succeeds.
        #
        # What that looked like: harbor-core in CrashLoopBackOff with
        # `password authentication failed for user "postgres"`, because the
        # password the chart put in `harbor-core` was gone by the time core
        # read it. Nothing before the pod logs said anything.
        #
        # `existingSecret` takes any name, so the collision was never
        # necessary.
        secretKey = gen "harbor-secret-key" "secretKey" 16;
        core = gen "harbor-core-secret" "secret" 16;
        xsrf = gen "harbor-xsrf" "CSRF_KEY" 32;
        jobservice = gen "harbor-jobservice-secret" "JOBSERVICE_SECRET" 16;
        registryHttp = gen "harbor-registry-http-secret" "REGISTRY_HTTP_SECRET" 16;

        # The registry's own credential. The chart derives the htpasswd from
        # the password with helm's `htpasswd`, which salts randomly and so
        # renders a different line every time; the template below does it in
        # the cluster instead, where a fresh salt costs nothing.
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

        # cert-manager issues it; the chart is told to use it.
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

          # Through the gateway, because that is the only name that resolves
          # from a node's container runtime — an in-cluster Service address
          # does not, and a pull happens outside the pod network.
          pullRef = host;

          credentials = {
            name = "harbor-admin";
            namespace = ns;
            usernameKey = "harbor-user";
            passwordKey = "HARBOR_ADMIN_PASSWORD";
          };
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          backs.registry = [ "harbor" ];

          bundles.harbor = kinds.mkBundle {
            createNamespaces = [ ns ];

            # All eight at the chart's appVersion. v2.13.1 was a guess and the
            # image gate named every one of them.
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
                # Signs the JWTs the registry checks on every pull, so it is a
                # CA rather than a leaf.
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

            # The six ExternalSecrets are resources here, so this bundle
            # causes them. The client credentials are not: kaniop writes those,
            # and kaniop is another floe's.
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

                # Every one of these points the chart at a Secret that already
                # exists rather than letting it mint one while rendering.
                # Without them the value is minted at build time: it lands in
                # the manifest, in the Nix store, and rotates on every apply.
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

                # Trivy pulls a vulnerability database on every start and is
                # several hundred megabytes of it. A lab that wants scanning
                # turns it on knowing that.
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
