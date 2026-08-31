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
      description = "Kanidm version the operator runs.";
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
        Reconcile `KanidmOAuth2Client` resources in any namespace.

        On, because a consumer renders its own client and a consumer lives in
        its own namespace. Off, kaniop looks only in this one: a client
        elsewhere is admitted, stored, and never reconciled, and the consumer
        waits for a Secret that is not coming. `kinds.mkOAuth2Client` refuses
        that combination rather than letting it render.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

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

        name = "kanidm";
        tlsSecret = "kanidm-tls";
      in
      {
        config.floe.provides.oidc = {
          readyToken = "server";

          # https, always. See `requires.issuance`.
          issuer = "https://${inputs.domain}";

          clientCrd = "kaniop.rs/KanidmOAuth2Client";
          ref = {
            inherit name;
            namespace = inputs.namespace;
          };
          inherit (inputs) clientsAnyNamespace;
        };

        config.floe.out.component = kinds.mkComponent {
          # Nothing here names an image: the operator decides what to run from
          # `spec.version`, and the tag it picks is not visible at eval. The
          # claim would be a claim about someone else's decision.
          imagesComplete = false;

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
                  inherit (inputs) domain version;
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

                  tlsSecretName = tlsSecret;
                  storage.volumeClaimTemplate.spec = {
                    accessModes = [ "ReadWriteOnce" ];
                    resources.requests.storage = inputs.storage;
                  };
                }
                // lib.optionalAttrs inputs.clientsAnyNamespace {
                  # An empty selector is "every namespace", which is what a
                  # consumer rendering its own client needs. Absent, kaniop
                  # looks only in this one.
                  oauth2ClientNamespaceSelector = { };
                };
              };
            };

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
