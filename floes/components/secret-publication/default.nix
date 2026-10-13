# A Secret this cluster minted, pushed into a lab store for another to read.
#
# The producer half of secret sharing. It was a lab option —
# `lab.clusters.<c>.secrets.publish` — rendering a `PushSecret` from the
# module, with the remote key derived from `(lab, cluster, namespace, secret)`
# on both sides and assertions checking that the two derivations agreed. The
# key is an input here and travels through `PUBLISHED_SECRET`, so the consumer
# reads it: nothing is derived twice, and there is nothing for an assertion to
# compare.
#
# Two things it needs are resolved rather than asserted. The store object has
# to be in *this* cluster — a `ClusterSecretStore` is not shared between
# clusters, only the backend behind it is — which is `requires.store`, refused
# by the linker when no store is here. And the store has to be writable, which
# is a field of what the store provides.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "secret-publication";
  summary = "Pushes a Secret this cluster holds into a lab store.";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      description = "Namespace holding the Secret to push. Required.";
    };

    secret = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of the Secret to push, as it is called here. Required.

        What it is called where it is read is the subscriber's choice, and
        neither name is one the other side has to know.
      '';
    };

    key = lib.mkOption {
      type = lib.types.str;
      description = ''
        Key it is written under in the store. Required.

        It used to be derived from the producing cluster's identity, on both
        sides, which is what made a mismatch between them possible at all.
      '';
    };

    keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Which keys of the Secret travel. Empty means the whole Secret, as one
        value.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.secretStore = sigs.SECRET_STORE;

  provides.publication = sigs.PUBLISHED_SECRET;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        store = config.floe.requires.secretStore;
      in
      {
        config.floe.provides.publication = {
          inherit (store) storeName;
          inherit (inputs) key keys;
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          assertions = [
            {
              assertion = store.writable;
              message =
                "pushes into '${store.storeName}', which is not writable. An authored store "
                + "is read-only and top-down: you write the value and it is projected into "
                + "every cluster that needs it. Sharing a value this cluster mints needs a "
                + "store a cluster may write back into.";
            }
          ];

          backs.publication = [ "publication" ];

          bundles.publication = kinds.mkBundle {
            needsSecrets = [ "${inputs.namespace}/${inputs.secret}" ];

            resources.push = {
              apiVersion = "external-secrets.io/v1alpha1";
              kind = "PushSecret";
              metadata = {
                name = "push-${config.floe.name}";
                inherit (inputs) namespace;
              };
              spec = {
                updatePolicy = "Replace";
                deletionPolicy = "Delete";
                secretStoreRefs = [
                  {
                    name = store.storeName;
                    kind = store.storeKind;
                  }
                ];
                selector.secret.name = inputs.secret;
                data =
                  if inputs.keys == [ ] then
                    [ { match.remoteRef.remoteKey = inputs.key; } ]
                  else
                    map (k: {
                      match = {
                        secretKey = k;
                        remoteRef = {
                          remoteKey = inputs.key;
                          property = k;
                        };
                      };
                    }) inputs.keys;
              };
            };
          };
        };
      }
    )
  ];
}
