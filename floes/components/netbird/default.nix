# netbird's control plane: an overlay network peers join and a UI to run it
# from.
#
# ## What this is, and what it is not
#
# Four workloads — management, signal, relay, dashboard — plus the two
# credentials they share and the OIDC client they authenticate against. That
# is a netbird you can log into and register a peer with.
#
# It is not the whole of NetBird, which is
# files. Three layers of it are not here and are named rather than omitted:
#
# **The operator** is `floes/cluster/netbird-operator`, a floe of its own. It
# is not part of this one because it does not have to run where this one does:
# a cluster with no control plane still reconciles mesh CRs against the
# control plane in another, which is what `MESH_NETWORK` crossing a lab scope
# is for. What stays here is the credential it spends — this floe mints the
# personal access token and promises where it landed (`MESH_ADMIN`).
#
# **The agent** is an in-cluster peer advertising the cluster's service range
# into the mesh, which is what makes one cluster reachable from another. It
# needs a setup key, so it needs the operator.
#
# **Routing** is the DNS and iptables plumbing that lets mesh traffic resolve
# and reach in-cluster names. It needs the agent.
#
# So this floe stands a mesh up and does not yet join anything to it
# automatically. A peer joins by hand with a key made in the dashboard, which
# is a real thing to do and is what the isolation suite and the lab check.
#
# ## One hostname, four backends
#
# Everything is on `<subdomain>.<zone>` and routed by path, which is how
# netbird itself is deployed and what its config assumes:
#
#     /api                             management   the REST API
#     /management.ManagementService/   management   the peer protocol, gRPC
#     /signalexchange.SignalExchange/  signal       the handshake broker, gRPC
#     /relay                           relay        the websocket fallback
#     /                                dashboard    the UI
#
# Giving management, signal and the dashboard a hostname each
# and this floe did too until it was stood up: `https://<api host>/` answered
# 404, because there is no page at the root of an API. That is indisistinguishable
# from a gateway with no route at all, which is why `lab.verify.endpoints`
# refuses to accept 404 — and it was right to. Putting the dashboard at `/`
# makes the root a real page, gives the relay the path its own config already
# advertises, and leaves one hostname to match the wildcard certificate
# instead of three.
{
  floe,
  lib,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "netbird";
  summary = "A NetBird control plane: management, signal, dashboard and its identity setup.";

  inputs = {
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "netbird";
      description = ''
        Label the mesh answers on, inside the gateway's zone.

        One hostname for all four backends, routed by path — see the header.
        A peer, a browser and the relay all reach `<subdomain>.<zone>`, so
        there is one name to match the wildcard certificate and one for a
        human to remember.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "netbird";
      description = "Namespace the control plane runs in.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.60.2";
      description = ''
        Version of management, signal and relay, which ship as one release.

        The relay protocol and the management config schema change together
        across releases, so these three are one number and not three.
      '';
    };

    dashboardVersion = lib.mkOption {
      type = lib.types.str;
      default = "v2.16.0";
      description = ''
        The dashboard, which is versioned separately from the server.

        Pinned rather than `main`, which is what netbird's own compose files
        use: a lab is reproducible or it is
        not.
      '';
    };

    registry = lib.mkOption {
      type = lib.types.str;
      default = "docker.io";
      description = "Registry every netbird image is pulled from.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "1Gi";
      description = ''
        Size of the volume management's sqlite store lives on.

        The whole mesh is in it: peers, keys, groups and policies. Losing it
        is losing every peer's registration.
      '';
    };
  };

  # Three routed hostnames, so a gateway and the CRDs it is written against.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # Claimed, so whatever answers for the zone learns this hostname from the
  # link rather than by reading what rendered. The gateway collects these.
  # ADR 0004.
  provides.route = sigs.ROUTE_CLAIM;

  # The relay secret and the datastore encryption key are minted in-cluster.
  # Neither may appear in a rendered manifest: one is a shared authenticator
  # and the other decrypts the store.
  requires.generation = sigs.SECRET_GENERATION;

  # Not optional. netbird has no local accounts at all — every identity comes
  # from a token — so a netbird with no issuer is one nobody can log into,
  # including the operator that would configure it.
  requires.oidc = sigs.OIDC_PROVIDER;

  # Management validates every token by fetching the issuer's signing keys
  # over HTTPS, and in a lab that issuer is served from the lab's own CA. A
  # container trusts public roots and nothing else, so without the bundle the
  # fetch fails x509 verification and *every* login is refused — with an error
  # about a certificate, from a component nobody was looking at.
  #
  # This is why the whole floe requires it. Nothing else in the tree required
  # TRUST_BUNDLE at all: trust-manager provided it and had no consumer, so the
  # lab distributed a CA that nothing was mounting. netbird is the first floe
  # that has to verify a peer inside the lab, and it found that out.
  requires.trust = sigs.TRUST_BUNDLE;

  # The `KanidmServiceAccount` below is inert without something reconciling
  # it, and inert here means the bootstrap Job waits forever on a Secret that
  # is never written. Required rather than assumed: the floe that installs the
  # operator and the floe that installs the issuer are different floes, and a
  # lab can have the second without the first.
  requires.identityOperator = sigs.IDENTITY_OPERATOR;

  provides.mesh = sigs.MESH_NETWORK;

  # Where the token that administers the mesh lands. A separate promise rather
  # than a field of MESH_NETWORK, because the two have opposite reach: the
  # mesh spans clusters and this is a Secret in one namespace of one of them.
  # `netbird-operator` resolves this when it runs beside the control plane and
  # is told where the token is when it does not.
  provides.meshAdmin = sigs.MESH_ADMIN;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;
        oidcProvider = config.floe.requires.oidc;
        trust = config.floe.requires.trust;

        ns = inputs.namespace;
        zone = gateway.baseDomain;

        apiDomain = "${inputs.subdomain}.${zone}";

        image = repo: tag: "${inputs.registry}/${repo}:${tag}";

        client = kinds.mkOAuth2Client {
          provider = oidcProvider;
          name = "netbird";
          namespace = ns;
          origin = "https://${apiDomain}";
          displayName = "NetBird";
          public = true;
          redirectUrls = [
            "https://${apiDomain}/peers"
            "https://${apiDomain}/add-peers"
          ];
        };

        serviceAccount = kinds.mkServiceAccount {
          provider = oidcProvider;
          name = "netbird-operator";
          namespace = ns;
          tokenSecret = "netbird-kanidm-token";
          displayName = "netbird-operator";
        };

        relaySecret = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = "netbird-relay-auth";
          key = "secret";
          length = 32;
          symbols = 0;
        };

        datastoreKey = kinds.mkGeneratedSecret {
          namespace = ns;
          secret = "netbird-datastore-key";
          key = "key";
          length = 32;
          encoding = "base64";
        };

        nb = {
          namespace = ns;
          labels."app.kubernetes.io/managed-by" = "catallaxy";

          inherit apiDomain;
          inherit (inputs) storage;

          managementHost = "netbird-management.${ns}.svc.cluster.local";
          signalHost = "netbird-signal.${ns}.svc.cluster.local";

          relaySecret = "netbird-relay-auth";
          relaySecretKey = "secret";
          datastoreKeySecret = "netbird-datastore-key";
          datastoreKeyKey = "key";

          inherit (client) oidc;

          caBundle = {
            inherit (trust.caBundle) name key;
            mountPath = "/etc/netbird-ca";
            filename = "lab-ca.crt";
            certDir = "/etc/ssl/certs:/etc/netbird-ca";
            volumeName = "lab-ca";
          };

          callbackUrls = [
            "https://${apiDomain}/peers"
            "https://${apiDomain}/add-peers"
          ];

          patSecret = "netbird-api-token";
          patKey = "token";

          serviceAccount = serviceAccount;

          managementInternalUrl = "http://netbird-management.${ns}.svc.cluster.local:80";

          images = {
            management = image "netbirdio/management" inputs.version;
            signal = image "netbirdio/signal" inputs.version;
            relay = image "netbirdio/relay" inputs.version;
            dashboard = image "netbirdio/dashboard" inputs.dashboardVersion;
            wait = image "busybox" "1.36";

            tools = image "alpine/k8s" "1.32.4";
          };
        };

        k8s = import ./k8s.nix { inherit lib nb; };
        management = import ./management.nix { inherit lib k8s nb; };
        workloads = import ./workloads.nix { inherit lib k8s nb; };
        automation = import ./automation.nix { inherit lib k8s nb; };

        meshRoute =
          let
            inZone = lib.hasSuffix ".${zone}" apiDomain;

            rule = path: service: port: {
              matches = [
                {
                  path = {
                    type = "PathPrefix";
                    value = path;
                  };
                }
              ];
              backendRefs = [
                {
                  name = service;
                  inherit port;
                }
              ];
            };
          in
          if !inZone then
            throw ''
              netbird asks for hostname '${apiDomain}', which is outside the
              gateway's zone '${zone}'. The gateway cannot serve it: the
              wildcard certificate does not cover it and no DNS in the lab
              answers for it.
            ''
          else
            {
              apiVersion = "gateway.networking.k8s.io/v1";
              kind = "HTTPRoute";
              metadata = {
                name = "netbird";
                namespace = ns;
                labels."app.kubernetes.io/managed-by" = "catallaxy";
              };
              spec = {
                parentRefs = [ gateway.parentRef ];
                hostnames = [ apiDomain ];
                rules = [
                  (rule "/api" "netbird-management" 80)
                  (rule "/management.ManagementService/" "netbird-management" 80)
                  (rule "/signalexchange.SignalExchange/" "netbird-signal" 80)
                  (rule "/relay" "netbird-relay" 33080)
                  (rule "/" "netbird-dashboard" 80)
                ];
              };
            };

        imageParts = repo: tag: {
          inherit (inputs) registry;
          repository = repo;
          inherit tag;
          digest = null;
        };
      in
      {
        config.floe.provides.mesh = {

          namespace = ns;
          managementUrl = "https://${apiDomain}";

          inherit (nb) managementInternalUrl;

          dashboardUrl = "https://${apiDomain}";
        };

        config.floe.provides.meshAdmin.tokenSecret = {
          namespace = ns;
          name = nb.patSecret;
          key = nb.patKey;
        };

        config.floe.provides.route.host = apiDomain;

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles = {
            credentials = kinds.mkBundle {
              createNamespaces = [ ns ];

              resources =
                relaySecret.resources
                // datastoreKey.resources
                // {
                  netbird-oauth2-client = client.resource;
                };

              secrets = relaySecret.secrets ++ datastoreKey.secrets;

              ready = relaySecret.ready;

              awaitRollout = false;
            };

            server = kinds.mkBundle {
              needs = [ "credentials" ];

              resources =
                management.resources
                // workloads.signal
                // workloads.relay
                // {
                  netbird-route = meshRoute;
                };

              images = {
                management = imageParts "netbirdio/management" inputs.version;
                signal = imageParts "netbirdio/signal" inputs.version;
                relay = imageParts "netbirdio/relay" inputs.version;
                wait = imageParts "busybox" "1.36";
              };

              ready = kinds.readyDeployment {
                name = "netbird-management";
                namespace = ns;
              };

              ops.mesh = {
                config = kinds.mkOpsCommand {
                  description = "Show what the running server substituted into its config";
                  command = [
                    "sh"
                    "-c"
                    ''
                      kubectl --context "$KUBE_CONTEXT" -n ${ns} \
                        exec deploy/netbird-management -c netbird-management -- \
                        sh -c 'grep -c "@RELAY_AUTH_SECRET@\|@DATASTORE_ENC_KEY@" /etc/netbird/management.json' \
                        | { read -r n; if [ "$n" = 0 ]; then
                              echo "config rendered: no placeholders remain"
                            else
                              echo "config NOT rendered: $n placeholder(s) still present" >&2
                              exit 1
                            fi; }
                    ''
                  ];
                };
              };
            };

            dashboard = kinds.mkBundle {
              resources = workloads.dashboard;

              images.dashboard = imageParts "netbirdio/dashboard" inputs.dashboardVersion;

              ready = kinds.readyDeployment {
                name = "netbird-dashboard";
                namespace = ns;
              };
            };

            automation = kinds.mkBundle {
              needs = [ "server" ];

              resources = automation.resources;

              images.tools = imageParts "alpine/k8s" "1.32.4";

              externalSecrets = [
                "${ns}/${nb.patSecret}"
                "${nb.serviceAccount.token.namespace}/${nb.serviceAccount.token.name}"
              ];

              ready = nb.serviceAccount.ready;
            };
          };

          backs.mesh = [ "server" ];
          backs.meshAdmin = [ "automation" ];
        };
      }
    )
  ];
}
