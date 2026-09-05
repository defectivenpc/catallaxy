# Harbor: an OCI registry with projects, users and scanning.
#
# 300 lines against the parked 1,320, and the difference is almost entirely
# option surface — the parked floe carried an option for every value the chart
# takes, and the example labs set six of them.
#
# What is *not* dropped is the six secrets. Left to itself the chart mints them
# with `randAlphaNum` while rendering, so all six land in the manifest, in the
# digest that pins it and in the Nix store, and all six change on any
# re-render. That is not only a leak: a rotating `REGISTRY_HTTP_SECRET`
# invalidates every in-flight upload, and a rotating core secret breaks
# core↔jobservice until every pod has restarted. Each is minted in-cluster
# instead, at the length Harbor requires.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "harbor";

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

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # Six of them, and the reason is in the header.
  requires.generation = sigs.SECRET_GENERATION;

  requiresOptional.oidc = sigs.OIDC_PROVIDER;

  provides.registry = sigs.OCI_REGISTRY;

  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;
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

        generated = [
          admin
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

          network = {
            declared = true;
            serves.http = {
              port = 8080;
              protocol = "TCP";
              fromExternal = false;
              fromApiServer = false;
            };
            reaches = [ ];
          };

          backs.registry = [ "harbor" ];

          bundles.harbor = kinds.mkBundle {
            createNamespaces = [ ns ];

            # All eight at the chart's appVersion. v2.13.1 was a guess and the
            # image gate named every one of them.
            images.core = {
              registry = "docker.io";
              repository = "goharbor/harbor-core";
              tag = "v2.15.1";
              digest = null;
            };
            images.portal = {
              registry = "docker.io";
              repository = "goharbor/harbor-portal";
              tag = "v2.15.1";
              digest = null;
            };
            images.jobservice = {
              registry = "docker.io";
              repository = "goharbor/harbor-jobservice";
              tag = "v2.15.1";
              digest = null;
            };
            images.registry = {
              registry = "docker.io";
              repository = "goharbor/registry-photon";
              tag = "v2.15.1";
              digest = null;
            };
            images.registryctl = {
              registry = "docker.io";
              repository = "goharbor/harbor-registryctl";
              tag = "v2.15.1";
              digest = null;
            };
            images.database = {
              registry = "docker.io";
              repository = "goharbor/harbor-db";
              tag = "v2.15.1";
              digest = null;
            };
            images.redis = {
              registry = "docker.io";
              repository = "goharbor/redis-photon";
              tag = "v2.15.1";
              digest = null;
            };
            images.nginx = {
              registry = "docker.io";
              repository = "goharbor/nginx-photon";
              tag = "v2.15.1";
              digest = null;
            };

            resources =
              lib.foldl' (acc: g: acc // g.resources) { } generated
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
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
            externalSecrets = lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.harbor = {
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
                existingSecretAdminPassword = "harbor-admin";
                existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD";
                existingSecretSecretKey = "harbor-secret-key";

                core = {
                  existingSecret = "harbor-core-secret";
                  existingXsrfSecret = "harbor-xsrf";
                  existingXsrfSecretKey = "CSRF_KEY";
                };
                jobservice = {
                  existingSecret = "harbor-jobservice-secret";
                  existingSecretKey = "JOBSERVICE_SECRET";
                };
                registry = {
                  existingSecret = "harbor-registry-http-secret";
                  existingSecretKey = "REGISTRY_HTTP_SECRET";
                };

                # Trivy pulls a vulnerability database on every start and is
                # several hundred megabytes of it. A lab that wants scanning
                # turns it on knowing that.
                trivy.enabled = false;
              };
            };

            ready = {
              kind = "condition";
              resource = "deployment/harbor-core";
              namespace = ns;
              condition = "Available";
              timeout = "10m";
            };
          };
        };
      }
    )
  ];
}
