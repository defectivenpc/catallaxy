# netbird's control plane: an overlay network peers join and a UI to run it
# from.
#
# ## What this is, and what it is not
#
# Four workloads — management, signal, relay, dashboard — plus the two
# credentials they share and the OIDC client they authenticate against. That
# is a netbird you can log into and register a peer with.
#
# It is not the whole of the parked floe, which was 4,890 lines across twenty
# files. Three layers of it are not here and are named rather than omitted:
#
# **The operator** (`netbird.io/Group`, `netbird.io/SetupKey`) reconciles mesh
# state from CRs, which is how a lab declares a setup key instead of clicking
# one. It authenticates to netbird's API with a personal access token, and
# that token is minted by a bootstrap Job that first authenticates *to kanidm*
# with a service-account credential. The new kanidm floe mints no service
# accounts, so that chain has a missing first link — it is the work this floe
# is blocked on, not something skipped for time.
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
# The parked floe gave management, signal and the dashboard a hostname each,
# and this floe did too until it was stood up: `https://<api host>/` answered
# 404, because there is no page at the root of an API. That is indisistinguishable
# from a gateway with no route at all, which is why `lab.verify.endpoints`
# refuses to accept 404 — and it was right to. Putting the dashboard at `/`
# makes the root a real page, gives the relay the path its own config already
# advertises, and leaves one hostname to match the wildcard certificate
# instead of three.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "netbird";

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
        use and what the parked floe carried: a lab is reproducible or it is
        not.
      '';
    };

    registry = lib.mkOption {
      type = lib.types.str;
      default = "docker.io";
      description = "Registry every netbird image is pulled from.";
    };

    operatorChart = lib.mkOption {
      type = lib.types.str;
      description = ''
        Store path of the netbird-operator chart. Required.

        The operator is what makes mesh state declarative: groups, setup keys,
        routers and the Services exposed on the mesh are all CRs it
        reconciles. Without it a lab is back to clicking a setup key into the
        dashboard and hoping nothing drifts.
      '';
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

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Three routed hostnames, so a gateway and the CRDs it is written against.
  requires.gateway = sigs.API_GATEWAY;

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
  requires.identity = sigs.IDENTITY_OPERATOR;

  provides.mesh = sigs.MESH_NETWORK;

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

        # The dashboard is a browser app: it cannot keep a secret, so it is a
        # public client and its code exchange is protected by PKCE instead.
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

        # The machine identity the token step authenticates as. kaniop mints
        # the account and the API token and rotates it, which is why this is a
        # CR and not a Job: an expiring credential owned by an operator is a
        # credential that heals.
        #
        # `netbird-operator`, not `netbird`: kanidm has one name namespace
        # across every principal kind and the OAuth2 client above already
        # holds that name. Both being `netbird` produced a 500 from kanidm
        # whose only honest reading was in kanidm's own log —
        # `AttrUnique("duplicate value detected") ... conflicting_with:
        # netbird@idm.<zone>` — while kaniop reported "Service account is not
        # present" and the Job waiting on the token said the token was
        # missing. Three components, none naming the cause.
        # `kanidmPrincipalsAreUnique` refuses it at eval now.
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

        # Exactly 32 bytes, base64: netbird uses it as an AES key and refuses
        # to start on any other length, with an error naming neither the field
        # nor the expected size.
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

          # Mounted into anything that dials an in-lab HTTPS endpoint, and
          # appended to the system roots rather than replacing them: netbird
          # also reaches public addresses, and a container told to trust only
          # the lab CA stops trusting everything else.
          caBundle = {
            inherit (trust.caBundle) name key;
            mountPath = "/etc/netbird-ca";
            filename = "lab-ca.crt";
            certDir = "/etc/ssl/certs:/etc/netbird-ca";
            volumeName = "lab-ca";
          };

          # Where a browser comes back to after logging in. The dashboard's
          # own paths; the CLI's `http://localhost:<port>/` callbacks belong
          # to the client layer, which is not here.
          callbackUrls = [
            "https://${apiDomain}/peers"
            "https://${apiDomain}/add-peers"
          ];

          patSecret = "netbird-api-token";
          patKey = "token";

          serviceAccount = serviceAccount;

          # Written once here and read by the provide, the operator's chart
          # values and the token step. Three readers of one string is exactly
          # the shape that drifts when it is spelled three times.
          managementInternalUrl = "http://netbird-management.${ns}.svc.cluster.local:80";

          images = {
            management = image "netbirdio/management" inputs.version;
            signal = image "netbirdio/signal" inputs.version;
            relay = image "netbirdio/relay" inputs.version;
            dashboard = image "netbirdio/dashboard" inputs.dashboardVersion;
            wait = image "busybox" "1.36";

            # kubectl, curl and jq in one image, which is what the token step
            # needs: it reads a Secret, talks to two HTTP APIs, and writes a
            # Secret back.
            tools = image "alpine/k8s" "1.32.4";
          };
        };

        k8s = import ./k8s.nix { inherit lib nb; };
        management = import ./management.nix { inherit lib k8s nb; };
        workloads = import ./workloads.nix { inherit lib k8s nb; };
        automation = import ./automation.nix {
          inherit
            lib
            k8s
            nb
            kinds
            ;
        };

        # One hostname, five rules. Written out rather than built with
        # `kinds.mkRoute`, which makes a single-backend route — the shape
        # every other floe wants and this one cannot use.
        #
        # Gateway API matches the most specific path first regardless of the
        # order they are written in, so `/` last is documentation rather than
        # semantics.
        meshRoute =
          let
            # The zone check `mkRoute` would have done. Kept, because it is
            # the reason a hostname here cannot be silently unservable: the
            # wildcard certificate covers the zone and nothing else, and no
            # DNS in the lab answers outside it.
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
          readyToken = "server";

          namespace = ns;
          managementUrl = "https://${apiDomain}";

          # What something inside this cluster dials. A peer outside uses the
          # routed name; the operator and the agent are in here with it, and
          # the routed name would leave the cluster and come back.
          inherit (nb) managementInternalUrl;

          # One name, so the UI and the API are the same origin.
          dashboardUrl = "https://${apiDomain}";
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          network = {
            declared = true;

            serves = {
              api = {
                port = 80;
                fromExternal = true;
              };
              grpc = {
                port = 33073;
                fromExternal = true;
              };
              signal = {
                port = 80;
                fromExternal = true;
              };
              relay = {
                port = 33080;
                fromExternal = true;
              };
              dashboard = {
                port = 80;
                fromExternal = true;
              };
            };

            # Management fetches the issuer's signing keys, and re-fetches
            # them when they rotate. That is the only thing here that leaves
            # the cluster.
            egress.internet.ports = [ 443 ];
          };

          bundles = {
            # Everything the servers read before they can start, and nothing
            # that reads anything. Separate from the servers so the wait is
            # the graph's rather than a pod's restart loop: the two Secrets
            # are mounted by `subPath`, and a pod whose subPath source does
            # not exist stays in `CreateContainerConfigError` rather than
            # retrying cleanly.
            credentials = kinds.mkBundle {
              createNamespaces = [ ns ];

              resources =
                relaySecret.resources
                // datastoreKey.resources
                // {
                  netbird-oauth2-client = client.resource;
                };

              secrets = relaySecret.secrets ++ datastoreKey.secrets;

              # The relay secret's key, not the object: external-secrets
              # creates the Secret before it has anything to put in it.
              ready = relaySecret.ready;

              # Nothing here is a workload.
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

              ready = {
                kind = "condition";
                resource = "deployment/netbird-management";
                namespace = ns;
                condition = "Available";
                timeout = "5m";
              };

              ops.mesh = {
                # The config the server is actually running, not the template
                # in the ConfigMap. The two differ by the substitution the
                # init container does, and "did the substitution happen" is
                # the question worth being able to ask — a placeholder that
                # survived is a server that starts and refuses every peer.
                #
                # `jq` over the whole file would print both credentials, so
                # this prints the keys and the two that must not still be
                # placeholders, and nothing else.
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
              # No route of its own: the one on `server` sends `/` here. A
              # second HTTPRoute for the same hostname would be a second set
              # of rules the gateway merges by specificity, which is a
              # decision nobody wrote down.
              resources = workloads.dashboard;

              images.dashboard = imageParts "netbirdio/dashboard" inputs.dashboardVersion;

              ready = {
                kind = "condition";
                resource = "deployment/netbird-dashboard";
                namespace = ns;
                condition = "Available";
                timeout = "5m";
              };
            };

            # The identity, and the one token nobody else owns.
            #
            # After the server, because it asks netbird a question before it
            # does anything — and before the operator, which cannot start
            # without the answer.
            automation = kinds.mkBundle {
              needs = [ "server" ];

              resources = automation.resources;

              images.tools = imageParts "alpine/k8s" "1.32.4";

              # Written by the Job, so nothing in the manifest stream creates
              # it and the reference rule would call it dangling. The
              # distinction is who to talk to when it is missing: this one is
              # a lab that has not finished starting, not a bug in the tree.
              externalSecrets = [
                "${ns}/${nb.patSecret}"
                "${nb.serviceAccount.token.namespace}/${nb.serviceAccount.token.name}"
              ];

              # kaniop has to have issued the service account's token before
              # the Job can exchange it. Waiting on the CR would report ready
              # while the token was still being minted.
              ready = nb.serviceAccount.ready;
            };

            operator = kinds.mkBundle {
              needs = [ "automation" ];

              helmCharts = (automation.operator { chart = inputs.operatorChart; }).helmCharts;

              needsSecrets = [ "${ns}/${nb.patSecret}" ];

              # The chart's own image, declared because the chart is opaque
              # until apply and an operator mirroring this lab into an airgap
              # gets what was declared and nothing else.
              images.operator = {
                registry = "ghcr.io";
                repository = "netbirdio/netbird-operator";
                tag = "v0.7.0";
                digest = null;
              };

              # The CRDs come from the chart, so a CR of these kinds is
              # ordered after it by the derived `kind:` edge rather than by
              # anything written here.
              crds = [
                "netbird.io/Group"
                "netbird.io/SetupKey"
                "netbird.io/NetworkRouter"
                "netbird.io/NetworkResource"
                "netbird.io/NBPolicy"
              ];

              ready = {
                kind = "condition";
                resource = "deployment/netbird-operator";
                namespace = ns;
                condition = "Available";
                timeout = "5m";
              };
            };
          };

          # What stands behind the promise: a consumer resolving MESH_NETWORK
          # waits for the servers, not for the UI in front of them.
          backs.mesh = [ "server" ];
        };
      }
    )
  ];
}
