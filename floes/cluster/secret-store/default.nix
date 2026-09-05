# A store this cluster can read secrets from, and write them back into.
#
# The floe half of secret sharing. It renders one `ClusterSecretStore` and
# says so through `SECRET_STORE`; the lab half — which cluster publishes what,
# and who subscribes — is wiring between clusters, which floe-core links
# cannot express and which therefore lives on the lab.
#
# Cluster-scoped rather than namespaced, because a value minted in one
# namespace is usually read in another, and a `SecretStore` is only visible to
# the namespace holding it.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "secret-store";

  inputs = {
    labStore = lib.mkOption {
      type = lib.types.str;
      description = ''
        The `lab.secrets.stores` entry this backs. Required.

        The rendered object's name is derived from it rather than given, so
        the lab wiring that references the store and this floe cannot end up
        naming different things.
      '';
    };

    server = lib.mkOption {
      type = lib.types.str;
      description = ''
        Base URL of the vault-compatible server. Required.

        Reachable from *every* cluster that uses the store. An in-cluster
        address resolves only inside the cluster running the store, and a
        subscriber elsewhere waits forever on something it cannot dial — the
        lab refuses that combination rather than letting it render.
      '';
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "secret";
      description = "KV mount path.";
    };

    version = lib.mkOption {
      type = lib.types.enum [
        "v1"
        "v2"
      ];
      default = "v2";
      description = ''
        KV engine version. Writing a v2 mount as though it were v1 succeeds
        and stores the wrong shape, which nothing notices until a reader gets
        an envelope where it expected a value.
      '';
    };

    tokenSecret = lib.mkOption {
      type = lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            default = "vault-token";
            description = "Secret holding the token this store authenticates with.";
          };
          key = lib.mkOption {
            type = lib.types.str;
            default = "token";
            description = "Key within it.";
          };
          namespace = lib.mkOption {
            type = lib.types.str;
            default = "external-secrets";
            description = ''
              Namespace holding it. A `ClusterSecretStore` is cluster-scoped,
              so it has to be told.

              An ordinary Secret, so the usual way to get one here is a
              projection from an authored store: sops holds the credential
              for the store, and the store holds the runtime values.
            '';
          };
        };
      };
      default = { };
      description = "Where the store's own credential lives.";
    };

    writable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether a cluster may push into it. False makes this a read-only
        mirror of values authored elsewhere, and the lab refuses a `publish`
        naming it.
      '';
    };

    caBundle = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "ConfigMap holding the CA.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              default = "ca.crt";
              description = "Key within it.";
            };
            namespace = lib.mkOption {
              type = lib.types.str;
              description = "Namespace holding it.";
            };
          };
        }
      );
      default = null;
      description = ''
        A CA to verify the store's certificate against.

        Needed whenever the lab hosts the store itself: it answers at a lab
        hostname over TLS the lab's own CA signed, and external-secrets
        verifies against the pod's trust store, which has never heard of it.
        Every lab-hosted store failed `InvalidProviderConfig` until something
        pointed at the CA the cluster already carries. A store elsewhere is
        signed by a public CA and must keep using the pod's own roots, so this
        is null by default.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # The CRDs and the validating webhook. Applying a ClusterSecretStore before
  # the webhook answers is rejected outright.
  requires.generation = sigs.SECRET_GENERATION;

  provides.store = sigs.SECRET_STORE;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        address = import ../../../lib/eval/secret-address.nix { inherit lib; };

        # One binding, two projections: the rendered object and the provide.
        storeName = address.storeResourceName inputs.labStore;

      in
      {
        config.floe.provides.store = {
          inherit storeName;
          storeKind = "ClusterSecretStore";
          inherit (inputs) writable;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.store = [ "store" ];
          imagesComplete = true;

          network = {
            declared = true;
            # The controller dials the store, which is usually outside the
            # cluster. Which host is not knowable from here.
            egress.internet.ports = [ 443 ];
          };

          bundles.store = kinds.mkBundle {
            # The token is an ordinary Secret this floe does not create — a
            # projection or an operator supplies it — and naming it is what
            # keeps the cluster's coherence check honest about the dependency.
            needsSecrets = [ "${inputs.tokenSecret.namespace}/${inputs.tokenSecret.name}" ];

            resources.store = {
              apiVersion = "external-secrets.io/v1beta1";
              kind = "ClusterSecretStore";
              metadata.name = storeName;
              spec.provider.vault = {
                inherit (inputs) server path version;
                auth.tokenSecretRef = {
                  inherit (inputs.tokenSecret) name key namespace;
                };
              }
              // lib.optionalAttrs (inputs.caBundle != null) {
                caProvider = {
                  type = "ConfigMap";
                  inherit (inputs.caBundle) name key namespace;
                };
              };
            };

            ready = {
              kind = "condition";
              resource = "clustersecretstore/${storeName}";
              condition = "Ready";
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
