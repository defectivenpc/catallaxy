# Kanidm: the lab's OIDC issuer.
#
# No Helm chart. kaniop installs a `kaniop.rs/Kanidm` CRD and reconciles it
# into a StatefulSet, so this floe's whole job is to render one CR and say
# where the issuer is — which is why it is 200 lines against the parked
# floe's 1,681.
#
# Most of that 1,681 was `oauth2Clients`: an attrset of client records the
# provider published, which six consumers indexed by an id each had invented.
# That is gone. kaniop registers `KanidmOAuth2Client`, so a client is an
# ordinary namespaced resource and each consumer renders its own with
# `kinds.mkOAuth2Client`. The provider collects nothing.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "kanidm";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kanidm";
      description = "Namespace the server runs in.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = ''
        DNS name the server answers as. Required.

        Not cosmetic: it goes into WebAuthn's relying-party id and into every
        issued token's issuer claim, so it must match the hostname clients
        actually reach — a mismatch is a credential that verifies nowhere.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.6.4";
      description = ''
        Kanidm version the operator runs, as the tag of `registry/repository`.

        Not `spec.version` on the CR: kaniop v1beta1 has no such field, and a
        `Kanidm` carrying one is refused by the API server with
        `.spec.version: field not declared in schema` — under server-side
        apply the whole object is rejected, so the floe installs nothing at
        all. What the CRD takes is `spec.image`, whose own default is
        `kanidm/server:latest`, which a lab that means to be reproducible
        cannot use.
      '';
    };

    registry = lib.mkOption {
      type = lib.types.str;
      default = "docker.io";
      description = "Registry the server image is pulled from.";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "kanidm/server";
      description = "Repository the server image lives in.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "1Gi";
      description = "Size of the volume the database lives on.";
    };

    clientsAnyNamespace = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Reconcile the resources consumers render — OAuth2 clients, service
        accounts and groups — in any namespace.

        On, because a consumer renders its own and a consumer lives in its own
        namespace. Off, kaniop looks only in this one: a resource elsewhere is
        admitted, stored, and never reconciled, and the consumer waits for a
        Secret that is not coming. `kinds.mkOAuth2Client` and
        `kinds.mkServiceAccount` refuse that combination rather than letting
        it render.

        Named for clients because that is what the `OIDC_PROVIDER` field is
        called and the signature is contract, but it has never been only about
        clients — it was only ever *set* for them, which is how netbird's
        service account came to sit unreconciled with an empty status.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # An issuer nobody can reach is not an issuer.
  #
  # This floe promised `https://<domain>` and rendered no route to it, so every
  # consumer in the tree — forgejo, harbor, argocd, grafana, netbird — was
  # configured against a hostname the lab answered with a 503 from its
  # ingress. Nothing caught it because no lab had ever logged in: the OIDC
  # path is the one thing an e2e that never opens a browser does not touch.
  requires.gateway = sigs.API_GATEWAY;

  # The gateway validates kanidm's certificate, which is signed by the lab CA.
  # Without the bundle the route attaches and every request through it fails
  # the backend handshake — the same class of failure as netbird's, one hop
  # earlier.
  requires.trust = sigs.TRUST_BUNDLE;

  # The CRD and something reconciling it. Without both, the CR below is a
  # resource of an unknown kind or a resource nothing acts on.
  requires.operator = sigs.IDENTITY_OPERATOR;

  # Kanidm serves TLS and will not start without a certificate. It is one of
  # the few servers with no plaintext mode at all — WebAuthn requires a secure
  # context, so there is nothing to fall back to.
  requires.issuance = sigs.X509_ISSUANCE;

  provides.oidc = sigs.OIDC_PROVIDER;

  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        operator = config.floe.requires.operator;
        issuance = config.floe.requires.issuance;
        gateway = config.floe.requires.gateway;
        trust = config.floe.requires.trust;

        name = "kanidm";
        tlsSecret = "kanidm-tls";

        image = "${inputs.registry}/${inputs.repository}:${inputs.version}";
      in
      {
        config.floe.provides.oidc = {
          readyToken = "server";

          # https, always. See `requires.issuance`.
          issuer = "https://${inputs.domain}";

          # kanidm's own paths, stated once here so no consumer has to know
          # them. `/ui/oauth2` is the browser-facing consent screen and not an
          # API path, which is the one a reader guesses wrong.
          authorizationEndpoint = "https://${inputs.domain}/ui/oauth2";
          tokenEndpoint = "https://${inputs.domain}/oauth2/token";

          clientCrd = "kaniop.rs/KanidmOAuth2Client";
          ref = {
            inherit name;
            namespace = inputs.namespace;
          };
          inherit (inputs) clientsAnyNamespace;
        };

        config.floe.out.component = kinds.mkComponent {
          # One image, and this floe picks it. It used to be `false` on the
          # grounds that the operator chose the tag from `spec.version` and
          # the choice was not visible at eval — true of a field the CRD does
          # not have. `spec.image` is the field it does have, so the decision
          # is this floe's and the claim is one it can make.
          imagesComplete = true;

          network = {
            declared = true;
            serves.https = {
              port = 8443;
              protocol = "TCP";
              fromExternal = false;
              fromApiServer = false;
            };
            reaches = [ ];
          };

          bundles.server = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            # So the lab's pull-through cache warms it and `cata images` can
            # see it. A `Kanidm` is a CR rather than a workload, so nothing
            # scraping the manifests for `image:` keys would find this.
            images.server = {
              inherit (inputs) registry repository;
              tag = inputs.version;
              digest = null;
            };

            # The CR is meaningless until the kind exists and something is
            # watching for it.
            needs = [ ];

            resources = {
              kanidm-cert = {
                apiVersion = "cert-manager.io/v1";
                kind = "Certificate";
                metadata = {
                  inherit name;
                  namespace = inputs.namespace;
                };
                spec = {
                  secretName = tlsSecret;
                  dnsNames = [ inputs.domain ];
                  inherit (issuance) issuerRef;
                };
              };

              kanidm = {
                apiVersion = "kaniop.rs/v1beta1";
                kind = "Kanidm";
                metadata = {
                  inherit name;
                  namespace = inputs.namespace;
                  labels."app.kubernetes.io/managed-by" = "catallaxy";
                };
                spec = {
                  inherit (inputs) domain;
                  inherit image;
                  origin = "https://${inputs.domain}";

                  # `replicaGroups`, not `replicas`: kaniop deploys each group
                  # as its own StatefulSet, and the CRD requires the list. A
                  # bare `replicas = 1` is admitted by nothing — the schema
                  # lint caught it before anything applied it.
                  replicaGroups = [
                    {
                      name = "default";
                      replicas = 1;
                      # Kanidm's write path is single-master, so a lab runs one
                      # writable node and no read replicas to be stale.
                      role = "write_replica";
                    }
                  ];

                  # kaniop renders the HTTPRoute and the BackendTLSPolicy from
                  # this, so the route is the operator's to own rather than a
                  # second resource this floe writes beside the CR and has to
                  # keep in step with it.
                  #
                  # `parentRef` comes off the signature: the gateway hands out
                  # its own attachment point, and a floe spelling the
                  # gateway's name and listener for itself is the by-name
                  # coupling `API_GATEWAY` exists to remove.
                  gateway = {
                    parentRefs = [ gateway.parentRef ];
                    hostnames = [ inputs.domain ];

                    # kanidm has no plaintext mode, so the hop from the
                    # gateway to it is HTTPS and the gateway has to trust what
                    # signed it.
                    backendTlsPolicy.validation = {
                      hostname = inputs.domain;
                      caCertificateRefs = [
                        {
                          group = "";
                          kind = "ConfigMap";
                          name = trust.caBundle.name;
                        }
                      ];
                    };
                  };

                  tlsSecretName = tlsSecret;
                  storage.volumeClaimTemplate.spec = {
                    accessModes = [ "ReadWriteOnce" ];
                    resources.requests.storage = inputs.storage;
                  };
                }
                // lib.optionalAttrs inputs.clientsAnyNamespace {
                  # An empty selector is "every namespace", which is what a
                  # consumer rendering its own kanidm resources needs. Absent,
                  # kaniop looks only in this one — and a resource outside it
                  # is admitted, stored, and never reconciled, which has no
                  # symptom beyond a consumer waiting forever.
                  #
                  # All three, not just the client. Only the OAuth2 selector
                  # was set, so netbird's `KanidmServiceAccount` sat with an
                  # empty status while the Job that needed its token
                  # crash-looped saying the token was missing — which was true
                  # and pointed one step short of the cause.
                  oauth2ClientNamespaceSelector = { };
                  serviceAccountNamespaceSelector = { };
                  groupNamespaceSelector = { };
                };
              };
            };

            # kaniop renders the HTTPRoute from `spec.gateway`, so nothing
            # here is a route the elaborator's walk can find — and the lab's
            # ingress builds its host map from that walk.
            routedHosts = [ inputs.domain ];

            # cert-manager writes it once the Certificate is issued, and the
            # operator mounts it. Nothing in these manifests reads it, so the
            # cluster has to be told it will exist.
            secrets = [ "${inputs.namespace}/${tlsSecret}" ];

            # The operator sets this once the server answers. Waiting on the
            # StatefulSet instead would report ready while kanidm was still
            # replaying its database.
            ready = {
              kind = "condition";
              resource = "kanidm/${name}";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "5m";
            };
          };

          # A consumer's client resource needs the CRD established and the
          # server answering; naming the bundle is what orders it after both
          # without the consumer knowing either name.
          backs.oidc = [ "server" ];

          assertions = [
            {
              assertion = issuance.issuerRef != null;
              message = "kanidm serves TLS only and cannot start without a certificate";
            }
          ];
        };
      }
    )
  ];
}
