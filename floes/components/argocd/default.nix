# Argo CD: the cluster reconciling itself from a git repository.
#
# The first consumer of GIT_REPOSITORY, and the reason that signature carries
# two URLs. Argo clones from *inside* the cluster, so the repository secret
# gets the Service address; a human opening the Application in the UI needs
# the routed one, and only one of those resolves in each place.
#
# It exposes no HA, dex or per-repo TLS settings, and no `oidc` block: a
# consumer registers its own client with `kinds.mkOAuth2Client`, so there is
# nothing here for a second one to duplicate.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "argocd";
  summary = "Argo CD, which takes ownership of applying the cluster's manifests.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the Argo CD Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
      description = "Namespace Argo CD runs in.";
    };

    waitTimeout = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        How long an apply may take to settle. On whatever applies, which
        once Argo is here is Argo.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Argo project the repository is registered under.";
    };

    insecureRepo = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Skip TLS verification when cloning.

        True by default, and only defensible because the repository this
        clones is inside the same cluster: `internalUrl` is a Service address
        over plain HTTP, so there is no certificate to verify in the first
        place. A lab pointing Argo at a repository outside itself should turn
        this off and give it a CA.
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

  # What it reconciles from. Exactly-one and not optional: an Argo CD with no
  # repository is a controller with nothing to do, and a lab that installed it
  # meant to hand the cluster over to something.
  requires.git = sigs.GIT_REPOSITORY;

  optional.oidc = sigs.OIDC_PROVIDER;

  provides.delivery = sigs.DELIVERY_POLICY;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;
        git = config.floe.requires.git;
        oidcProvider = config.floe.requires.oidc or null;

        ns = inputs.namespace;
        host = "argocd.${gateway.baseDomain}";

        adminSecret = "argocd-admin";

        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = adminSecret;
          key = "password";
          length = 24;
          symbols = 0;
          extraData.username = "admin";
        };

        redis = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = "argocd-redis";
          key = "auth";
          length = 32;
          symbols = 0;
        };

        client =
          if oidcProvider == null then
            { }
          else
            kinds.mkOAuth2Client {
              provider = oidcProvider;
              name = "argocd";
              namespace = ns;
              origin = "https://${host}";
              redirectUrls = [ "https://${host}/auth/callback" ];
            };
      in
      {
        config.floe.provides.delivery = {
          strategy = "argocd";
          bootstrapTool = "kubectl-ssa";
          inherit (inputs) waitTimeout;

          inherit (config.floe.requires.cluster) context;
        };

        config.floe.provides.route.host = host;

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.argocd = kinds.mkBundle {
            createNamespaces = [ ns ];

            images.argocd = {
              registry = "quay.io";
              repository = "argoproj/argocd";
              tag = "v3.0.1";
              digest = null;
            };
            images.redis = kinds.mkImage "public.ecr.aws/docker/library/redis:7.2.8-alpine";

            resources =
              admin.resources
              // redis.resources
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
                argocd-repo = {
                  apiVersion = "v1";
                  kind = "Secret";
                  metadata = {
                    name = "argocd-repo-lab";
                    namespace = ns;
                    labels."argocd.argoproj.io/secret-type" = "repository";
                  };
                  type = "Opaque";
                  stringData = {
                    type = "git";

                    url = lib.replaceStrings [ git.externalUrl ] [ git.internalUrl ] git.cloneUrl;

                    inherit (inputs) project;
                  }
                  // lib.optionalAttrs inputs.insecureRepo { insecure = "true"; };
                };

                argocd-route = kinds.mkRoute {
                  inherit gateway;
                  name = "argocd";
                  namespace = ns;
                  service = "argocd-server";
                  port = 80;
                };
              };

            secrets = admin.secrets ++ redis.secrets;
            needsSecrets = lib.optional (
              git.credentials != null
            ) "${git.credentials.namespace}/${git.credentials.name}";

            externalSecrets = lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.argocd = kinds.mkHelmChart {
              replacedHooks.argocd-redis-secret-init =
                "the floe mints `argocd-redis` itself with `kinds.mkGeneratedSecret`, "
                + "so the credential exists before anything reads it";
              inherit (inputs) chart;
              releaseName = "argocd";
              namespace = ns;
              values = {
                redis-ha.enabled = false;
                controller.replicas = 1;
                repoServer.replicas = 1;
                server.replicas = 1;

                dex.enabled = false;

                configs = {
                  params."server.insecure" = true;

                  cm = {
                    url = "https://${host}";
                  }
                  // lib.optionalAttrs (client != { }) {
                    "oidc.config" = ''
                      name: Kanidm
                      issuer: ${oidcProvider.issuer}
                      clientID: $${adminSecret}:oidc-client-id
                      clientSecret: $${${client.secret.name}}:${client.secret.secretKey}
                      requestedScopes: ["openid", "profile", "email", "groups"]
                    '';
                  };
                };
              };
            };

            ready = kinds.readyDeployment {
              name = "argocd-server";
              namespace = ns;
              timeout = "10m";
            };

            ops.cd = {
              apps = kinds.mkOpsCommand {
                description = "Every Application and its sync status";
                command = [
                  "kubectl"
                  "-n"
                  ns
                  "get"
                  "applications.argoproj.io"
                  "-o"
                  "custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status"
                ];
              };
            };
          };
        };
      }
    )
  ];
}
