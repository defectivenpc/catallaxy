# Kanidm: the lab's OIDC issuer.
#
# No Helm chart. kaniop installs a `kaniop.rs/Kanidm` CRD and reconciles it
# into a StatefulSet, so this floe's whole job is to render one CR and say
# where the issuer is.
#
# It publishes no client registry. kaniop registers `KanidmOAuth2Client`, so a
# client is an ordinary namespaced resource and each consumer renders its own
# with `kinds.mkOAuth2Client` — the provider collects nothing, and no consumer
# has to invent an id for itself.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "kanidm";
  summary = "Kanidm as the lab's OIDC provider, reconciled by kaniop.";

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

  # An issuer nobody can reach is not an issuer.
  #
  # This floe promised `https://<domain>` and rendered no route to it, so every
  # consumer in the tree — forgejo, harbor, argocd, grafana, netbird — was
  # configured against a hostname the lab answered with a 503 from its
  # ingress. Nothing caught it because no lab had ever logged in: the OIDC
  # path is the one thing an e2e that never opens a browser does not touch.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # The gateway validates kanidm's certificate, which is signed by the lab CA.
  # Without the bundle the route attaches and every request through it fails
  # the backend handshake — the same class of failure as netbird's, one hop
  # earlier.
  requires.trust = sigs.TRUST_BUNDLE;

  # The CRD and something reconciling it. Without both, the CR below is a
  # resource of an unknown kind or a resource nothing acts on.
  requires.identityOperator = sigs.IDENTITY_OPERATOR;

  # Kanidm serves TLS and will not start without a certificate. It is one of
  # the few servers with no plaintext mode at all — WebAuthn requires a secure
  # context, so there is nothing to fall back to.
  requires.issuance = sigs.X509_ISSUANCE;

  provides.oidc = sigs.OIDC_PROVIDER;

  # Claimed, like any other routed hostname. This floe is the one that cannot
  # be read off what rendered — kaniop builds the HTTPRoute from `spec.gateway`
  # and there is no route in these manifests for the elaborator's walk to
  # find — so `routedHosts` existed to tell the walk about it anyway. That
  # reached the ingress, which read the walk, and never reached the resolver,
  # which reads the claims: `idm.<zone>` was routed by the proxy and answered
  # by nothing. Claiming it is the statement both read. ADR 0004.
  provides.route = sigs.ROUTE_CLAIM;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        operator = config.floe.requires.identityOperator;
        issuance = config.floe.requires.issuance;
        gateway = config.floe.requires.gateway;
        trust = config.floe.requires.trust;

        name = "kanidm";
        tlsSecret = "kanidm-tls";

        image = "${inputs.registry}/${inputs.repository}:${inputs.version}";
      in
      {
        config.floe.provides.route.host = inputs.domain;

        config.floe.provides.oidc = {

          issuer = "https://${inputs.domain}";

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
          imagesComplete = true;

          bundles.server = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.server = {
              inherit (inputs) registry repository;
              tag = inputs.version;
              digest = null;
            };

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

              kanidm-backend-tls = {
                apiVersion = "gateway.networking.k8s.io/v1alpha3";
                kind = "BackendTLSPolicy";
                metadata = {
                  name = "kanidm";
                  namespace = inputs.namespace;
                  labels."app.kubernetes.io/managed-by" = "catallaxy";
                };
                spec = {
                  targetRefs = [
                    {
                      group = "";
                      kind = "Service";
                      inherit name;
                    }
                  ];
                  validation = {
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

                  replicaGroups = [
                    {
                      name = "default";
                      replicas = 1;
                      role = "write_replica";
                    }
                  ];

                  gateway = {
                    parentRefs = [ gateway.parentRef ];
                    hostnames = [ inputs.domain ];
                  };

                  tlsSecretName = tlsSecret;
                  storage.volumeClaimTemplate.spec = {
                    accessModes = [ "ReadWriteOnce" ];
                    resources.requests.storage = inputs.storage;
                  };
                }
                // lib.optionalAttrs inputs.clientsAnyNamespace {
                  oauth2ClientNamespaceSelector = { };
                  serviceAccountNamespaceSelector = { };
                  groupNamespaceSelector = { };
                };
              };
            };

            routedHosts = [ inputs.domain ];

            secrets = [ "${inputs.namespace}/${tlsSecret}" ];

            ready = kinds.readyCondition {
              resource = "kanidm/${name}";
              condition = "Available";
              namespace = inputs.namespace;
            };
          };

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
