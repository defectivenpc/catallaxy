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
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "argocd";
  summary = "Argo CD, which takes ownership of applying the cluster's manifests.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the Argo CD Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "argocd";
      description = "Namespace Argo CD runs in.";
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

  requires.gateway = sigs.API_GATEWAY;
  requires.generation = sigs.SECRET_GENERATION;

  # What it reconciles from. Exactly-one and not optional: an Argo CD with no
  # repository is a controller with nothing to do, and a lab that installed it
  # meant to hand the cluster over to something.
  requires.git = sigs.GIT_REPOSITORY;

  requiresOptional.oidc = sigs.OIDC_PROVIDER;

  provides.delivery = sigs.DELIVERY_POLICY;

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

        # The chart's own `configs.secret.argocdServerAdminPassword` is a
        # bcrypt hash it expects in the values — so a lab either commits a hash
        # or lets the chart generate one at render time. Minted in-cluster
        # instead, and the server reads it from the Secret the chart already
        # looks for.
        admin = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = adminSecret;
          key = "password";
          length = 24;
          symbols = 0;
          extraData.username = "admin";
        };

        # `argocd-redis` holds the password four workloads authenticate to
        # Redis with, and the Redis pod itself reads the same key to set
        # `--requirepass` — so minting it here gives both halves one value.
        #
        # The chart creates it from a `post-install` hook, and a hook is not a
        # rendered manifest: this renders with `helm template`, so the Job
        # never exists and the Secret never appears. Declaring it as "arrives
        # later" satisfied the lint and nothing else. Four workloads sat in
        # CreateContainerConfigError for the full ten minutes, which is how
        # `gitops.local` found it on its first real run — and is exactly what
        # a lab that only renders cannot tell you.
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
        # Argo is what applies things now, so the cluster's manifests are for
        # it to read rather than for `cata` to push. `bootstrapTool` stays
        # `kubectl-ssa`: something has to apply Argo itself, and it cannot be
        # Argo.
        config.floe.provides.delivery = {
          strategy = "argocd";
          bootstrapTool = "kubectl-ssa";
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.argocd = kinds.mkBundle {
            createNamespaces = [ ns ];

            images.argocd = {
              registry = "quay.io";
              repository = "argoproj/argocd";
              # The chart's appVersion. v3.2.5 was a guess.
              tag = "v3.0.1";
              digest = null;
            };
            # The chart pulls Redis from ECR, not Docker Hub, and the
            # repository path carries `docker/` in front of `library/`. Both
            # halves were wrong in the first draft and the gate named the ref.
            images.redis = kinds.mkImage "public.ecr.aws/docker/library/redis:7.2.8-alpine";

            resources =
              admin.resources
              // redis.resources
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
                # How Argo finds the repository. A Secret with this label is
                # what Argo watches for; there is no CRD for a repository.
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

                    # The in-cluster address. Argo clones from inside the
                    # cluster, and the routed name resolves through the
                    # gateway — which is a longer path to the same server, and
                    # one that needs the lab's CA to verify.
                    # The repository, over the in-cluster address. Argo needs
                    # a repository like anything else that clones, and the
                    # server address alone answers 503.
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
            # The repository Secret above names it but does not carry it, and
            # nothing here creates it — the git server does.
            needsSecrets = lib.optional (
              git.credentials != null
            ) "${git.credentials.namespace}/${git.credentials.name}";

            externalSecrets = lib.optional (client != { }) "${ns}/${client.secret.name}";

            helmCharts.argocd = {
              inherit (inputs) chart;
              releaseName = "argocd";
              namespace = ns;
              values = {
                # One of each. The chart's defaults are an HA topology with a
                # Redis cluster, which is three more workloads than a lab
                # reconciling one repository needs.
                redis-ha.enabled = false;
                controller.replicas = 1;
                repoServer.replicas = 1;
                server.replicas = 1;
                applicationSet.enabled = false;

                # Its own OIDC is `dex`, a second identity provider inside the
                # cluster that already has one. Argo talks to the issuer
                # directly instead.
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
