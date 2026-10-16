# Lab-held material, landed in this cluster as a Secret.
#
# The cluster asks and `cata` fills: the value is decrypted from a store on
# the operator's machine and applied, so no secret passes through evaluation
# and none reaches the store path. What the floe contributes is the
#
# It was `lab.clusters.<c>.secrets.project`, which made it the last thing a
# lab handed down: the elaborator took the map as a parameter and synthesised
# a bundle per entry on the cluster's behalf. A cluster's content is entirely
# its own floes' now.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "secret-projection";
  summary = "Asks `cata` to fill a Secret here from a lab store.";

  inputs = {
    secret = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of the Secret this lands as. Required.

        `cata` renders `metadata.name` from it, so it is the name whatever
        mounts the Secret must use.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Namespace it lands in.";
    };

    keys = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            from = lib.mkOption {
              type = lib.types.str;
              description = "Key of the managed secret this key reads.";
            };

            transform = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "How the value is rewritten on the way in, or null for verbatim.";
            };

            jsonKey = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "A field of a JSON value, for a source that holds a document.";
            };
          };
        }
      );
      default = { };
      description = "The Secret's keys, and where each comes from.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Which authored secret supplies the values, resolved rather than spelled. It was
  # `source = "<name>"` naming an attribute under `lab.secrets.managed` with
  # nothing checking it, so a typo left a Secret `cata` had no values for and
  # whatever mounted it waited forever on a key nothing would write.
  #
  # Resolving it also means the keys are known here, so `from` naming a key
  # the secret does not hold is refused where the projection is written.
  requires.labSecret = sigs.LAB_SECRET;

  out.projections = kinds.projections;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        secret = config.floe.requires.labSecret;

        absent = lib.unique (
          lib.filter (from: !(lib.elem from secret.readableKeys)) (
            lib.mapAttrsToList (_: k: k.from) inputs.keys
          )
        );
      in
      {
        config.floe.out.projections.${inputs.secret} =
          if absent != [ ] then
            throw (
              "secret-projection '${inputs.secret}': reads "
              + lib.concatMapStringsSep ", " (k: "'${k}'") absent
              + " from authored secret '${secret.name}', which holds "
              + lib.concatMapStringsSep ", " (k: "'${k}'") secret.readableKeys
              + ". `cata` would apply a Secret missing those keys and whatever mounts it "
              + "would wait on a key nothing writes."
            )
          else
            {
              source = secret.name;
              inherit (inputs) namespace;
              keys = lib.mapAttrs (_: k: { inherit (k) from transform jsonKey; }) inputs.keys;
            };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.projection = kinds.mkBundle {
            secrets = [ "${inputs.namespace}/${inputs.secret}" ];
          };
        };
      }
    )
  ];
}
