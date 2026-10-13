# One secret the lab holds, and the keys in it.
#
# **Authored**, which is the whole of what the name is for: this is material a
# human or an external system wrote down, the one kind no floe can mint for
# itself. A floe wanting a *random* credential does not come here — it mints
# one in its own bundle with `kinds.mkGeneratedSecret` and publishes the
# coordinates on its provide. The distinction decides which of the two a reader
# is looking at, and it used to be carried by a paragraph rather than a name:
# this was `lab-secret`, one letter from `lab-secrets`, which is the collector
# that folds every one of these into what the CLI reads.
#
# Which store backs it is resolved, not spelled: it `requires` a
# `LAB_SECRET_STORE`, so a lab with one store needs to say nothing and a lab
# with several says which with `.bind`. It was `store = "<name>"` under
# `lab.secrets.managed`, guarded by an assertion comparing the string against
# the declared stores — which is resolution, written out by hand.
#
# Nothing here holds a value. `keys` says what the secret contains and how
# `cata secrets generate` mints each one; the values live in the store.
#
# Its *unit name* is the secret's name, which is what
# `cata secrets edit <store> <secret>` takes and what a projection resolves.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "lab-authored-secret";
  summary = "A value a human or an external system authored, held in a lab store.";

  inputs = {
    kind = lib.mkOption {
      type = lib.types.enum [
        "value"
        "ca"
      ];
      default = "value";
      description = ''
        `ca` mints a self-signed certificate and key together, and always
        carries `ca.crt` and `ca.key` — together, because the certificate is
        signed by that key and generating them separately does not compose.
      '';
    };

    keys = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            generator = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "base64"
                  "hex"
                  "alphanumeric"
                  "uuid"
                ]
              );
              default = null;
              description = ''
                How `cata secrets generate` mints this key. Null means you set
                it by hand with `cata secrets edit`.

                An enum, though the CLI takes any string: an unknown generator
                is only rejected when someone runs the mint, and by then the
                store file exists and the failure looks like a tooling
                problem.
              '';
            };

            length = lib.mkOption {
              type = lib.types.nullOr lib.types.ints.positive;
              default = null;
              description = ''
                Entropy in bytes for `base64`, characters otherwise. Required
                by every generator but `uuid`, and capped at 4096 by the CLI.
              '';
            };
          };
        }
      );
      default = { };
      description = "The keys this secret holds.";
    };

    hostPaths = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
      };
      description = ''
        Keys to write to the host during `cata lab up`'s preflight, before any
        service starts. `$LAB_STATE_DIR` expands to the lab's state directory.

        A key named `*.crt` is written 0644 and everything else 0600 — the CLI
        decides on the suffix, not on `kind`, so a file that must be
        world-readable has to be named for it.
      '';
    };
  };

  requires.labStore = sigs.LAB_SECRET_STORE;

  provides.labSecret = sigs.LAB_SECRET;

  body =
    {
      inputs,
      requires,
      floe,
      ...
    }:
    let
      keyNames = lib.unique (
        lib.attrNames inputs.keys
        ++ lib.optionals (inputs.kind == "ca") [
          "ca.crt"
          "ca.key"
        ]
      );

      unwritable = lib.attrNames (lib.filterAttrs (k: _: !(lib.elem k keyNames)) inputs.hostPaths);
    in
    {
      provides.labSecret =
        if unwritable != [ ] then
          throw (
            "lab-authored-secret '${floe.name}': hostPaths names ${
              lib.concatMapStringsSep ", " (k: "'${k}'") unwritable
            }, which this secret does not hold. "
            + "Its keys are ${lib.concatMapStringsSep ", " (k: "'${k}'") keyNames}. "
            + "The preflight would write nothing and every service mounting the path would "
            + "start against a file that is not there."
          )
        else
          {
            name = floe.name;
            readableKeys = keyNames;
            store = requires.labStore.name;
            inherit (inputs) kind hostPaths;
            keys = lib.mapAttrs (_: k: { inherit (k) generator length; }) inputs.keys;
          };
    };
}
