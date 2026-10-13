# A store on the operator's machine, holding values nothing in a lab can mint.
#
# A floe that wants a *random* credential does not come here: it mints one in
# its own bundle with `kinds.mkGeneratedSecret` and publishes the coordinates
# on its provide. What is left is the material no floe can generate — a value
# a human authored, or one an external system holds.
#
# This floe never holds a value. Everything here says where values live;
# `cata` opens the store, reads it and applies what it finds, and nothing
# secret-shaped reaches the Nix store. That is not a nicety: a chart that
# minted its own credential at render time put it in the manifest, in the
# digest pinning the manifest, and in the store, and rotated it on every
# render.
#
# Its *unit name* is the store's name, because that is what
# `cata secrets edit <store>` takes.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "lab-secret-store";
  summary = "A sops file, a set of environment variables, or a vault, as something a floe can resolve.";

  inputs = {
    backend = lib.mkOption {
      type = lib.types.enum [
        "sops"
        "env"
        "vault"
        "external"
      ];
      default = "sops";
      description = ''
        Where this store's keys live.

        `sops`: an encrypted file at `secrets/<lab>/<store>.enc.yaml`.
        `env`: one environment variable per key, named
        `CATA_SECRET_<STORE>__<SECRET>__<KEY>` — uppercased, with every
        character that is not a letter or digit replaced by an underscore. The
        name is derived, so there is nothing to declare and nothing to keep in
        sync.
        `vault`, `external`: held somewhere outside catallaxy.
      '';
    };

    writerCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [
        "vault-put"
        "--mount"
        "lab"
      ];
      description = ''
        How to write a value into this store.

        It receives `CATA_SECRET_KEY` in the environment and the value on
        stdin, and must exit non-zero if the write did not happen. Nothing is
        passed on the command line, so a value never reaches a process
        listing. This is what makes the set of backends open.
      '';
    };

    removerCommand = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [
        "vault-delete"
        "--mount"
        "lab"
      ];
      description = ''
        How to remove a value from this store, for when the thing that
        produced it is destroyed.

        Same contract as `writerCommand` minus the value: it receives
        `CATA_SECRET_KEY` and must exit non-zero if the key is still there. A
        store with no remover is not an error — destroying a stack says what
        it could not take back rather than refusing to finish.
      '';
    };

    vaultServer = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Base URL of the vault-compatible server, for a `vault` backend.

        What `cata` dials from the *host*, so a routed name and not an
        in-cluster address. A cluster's own `VAULT_SERVER` answers the latter
        and is no use here, which is why nothing fills this automatically.
      '';
    };

    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = "secret";
      description = "KV mount path.";
    };

    vaultVersion = lib.mkOption {
      type = lib.types.enum [
        "v1"
        "v2"
      ];
      default = "v2";
      description = ''
        KV engine version.

        An enum here though the CLI parses it as a plain string, because
        writing a v2 mount as though it were v1 succeeds and stores the wrong
        shape — which nothing notices until a reader gets an envelope where it
        expected a value.
      '';
    };
  };

  provides.labStore = sigs.LAB_SECRET_STORE;

  body =
    { inputs, floe, ... }:
    let
      writable = lib.elem inputs.backend [
        "vault"
        "external"
      ];
    in
    {
      provides.labStore = {
        name = floe.name;
        inherit writable;
        inherit (inputs) backend writerCommand removerCommand;

        vault = {
          server = inputs.vaultServer;
          path = inputs.vaultPath;
          version = inputs.vaultVersion;
        };
      };
    };
}
