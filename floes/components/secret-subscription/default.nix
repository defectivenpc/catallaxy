# A value another cluster published, materialised here as a Secret.
#
# The consumer half of secret sharing, and the half that shows what the link
# buys: the key it reads is `requires.publication.key`, which is the producer's
# own, handed over by whatever placed both clusters. It was
# `lab.clusters.<c>.secrets.subscribe` naming the producing cluster by name,
# with the module deriving the same address on both sides and an assertion
# checking the two derivations matched — because a name that did not match left
# this ExternalSecret waiting forever on a key nothing wrote.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "secret-subscription";
  summary = "Materialises a value another cluster published, as a Secret here.";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Namespace the Secret lands in.";
    };

    secret = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name the value is called here. Required.

        What it was called where it was minted is the producer's business;
        this is a name that says what it is in this cluster.
      '';
    };

    refreshInterval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = ''
        How often the value is read again.

        A refresh, not a re-mint: the producer owns the value and this reads
        it, so an interval here costs a read and never a new credential.
      '';
    };

    labels = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Labels on the Secret, for what finds it by label rather than by name.";
    };

    annotations = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Annotations on the Secret.";
    };

    fields = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Template for the Secret's data, for a consumer that wants the value
        under a key of its own choosing.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires = {
    secretStore = sigs.SECRET_STORE;
    publication = sigs.PUBLISHED_SECRET;
  };

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        store = config.floe.requires.secretStore;
        publication = config.floe.requires.publication;
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          assertions = [
            {
              assertion = store.storeName == publication.storeName;
              message =
                "reads from '${publication.storeName}' and this cluster's store is "
                + "'${store.storeName}'. They are two backends, so the key the producer "
                + "wrote is not in the store this cluster would read — the ExternalSecret "
                + "would wait forever on a key nothing wrote.";
            }
          ];

          bundles.subscription = kinds.mkBundle {
            resources.pull = {
              apiVersion = "external-secrets.io/v1beta1";
              kind = "ExternalSecret";
              metadata = {
                name = "subscribe-${config.floe.name}";
                inherit (inputs) namespace;
              };
              spec = {
                inherit (inputs) refreshInterval;
                secretStoreRef = {
                  name = store.storeName;
                  kind = store.storeKind;
                };
                target = {
                  name = inputs.secret;
                  creationPolicy = "Owner";
                }
                // lib.optionalAttrs (inputs.fields != { } || inputs.labels != { } || inputs.annotations != { }) {
                  template = {
                    engineVersion = "v2";
                    metadata = {
                      inherit (inputs) labels annotations;
                    };
                  }
                  // lib.optionalAttrs (inputs.fields != { }) { data = inputs.fields; };
                };
                dataFrom = [ { extract.key = publication.key; } ];
              };
            };
          };
        };
      }
    )
  ];
}
