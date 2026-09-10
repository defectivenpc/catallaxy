# Secret material the lab holds, and where it comes from.
#
# Narrowly scoped on purpose. A floe that wants a random credential mints one
# itself with `kinds.mkGeneratedSecret` and publishes the coordinates on its
# own provide; nothing about that needs the lab. What is left here is the
# material no floe can generate — a value a human authored, or one an external
# system holds — and getting it to the cluster that needs it.
#
# The lab never holds a value. Everything below is a description of where a
# value lives; `cata` reads it, decrypts it and applies it, and nothing
# secret-shaped reaches the Nix store. That is not a nicety: a chart that
# minted its own credential at render time put it in the manifest, in the
# digest pinning the manifest, and in the store, and rotated it on every
# render.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  cfg = config.lab.secrets;

  # Which backends a cluster can write back into. Derived from the backend
  # rather than declared, so the two cannot disagree — and it is what decides
  # whether a secret can travel between clusters at all.
  runtimeBackends = [
    "vault"
    "external"
  ];

  storeType = types.submodule (
    { config, ... }:
    {
      options = {
        backend = mkOption {
          type = types.enum [
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
            character that is not a letter or digit replaced by an
            underscore. The name is derived, so there is nothing to declare
            and nothing to keep in sync.
            `vault`, `external`: held somewhere outside catallaxy.
          '';
        };

        direction = mkOption {
          type = types.enum [
            "authored"
            "runtime"
          ];
          readOnly = true;
          default = if lib.elem config.backend runtimeBackends then "runtime" else "authored";
          defaultText = lib.literalExpression "\"runtime\" for a vault or external backend";
          description = ''
            Whether anything may write into this store at runtime.

            `authored` stores are read-only and top-down: you write the value,
            catallaxy decrypts it at deploy and projects it into every cluster
            that needs it. A cluster cannot write back — for `sops` that would
            mean committing to your repository.
          '';
        };

        writer.command = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          example = [
            "vault-put"
            "--mount"
            "lab"
          ];
          description = ''
            How to write a value into this store.

            It receives `CATA_SECRET_KEY` in the environment and the value on
            stdin, and must exit non-zero if the write did not happen. Nothing
            is passed on the command line, so a value never reaches a process
            listing. This is what makes the set of backends open.
          '';
        };

        remover.command = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          example = [
            "vault-delete"
            "--mount"
            "lab"
          ];
          description = ''
            How to remove a value from this store, for when the thing that
            produced it is destroyed.

            Same contract as `writer.command` minus the value: it receives
            `CATA_SECRET_KEY` and must exit non-zero if the key is still
            there. A store with no remover is not an error — destroying a
            stack says what it could not take back rather than refusing to
            finish.
          '';
        };

        vault = {
          server = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Base URL of the vault-compatible server.";
          };
          path = mkOption {
            type = types.str;
            default = "secret";
            description = "KV mount path.";
          };
          version = mkOption {
            type = types.enum [
              "v1"
              "v2"
            ];
            default = "v2";
            description = ''
              KV engine version.

              An enum here though the CLI parses it as a plain string, because
              writing a v2 mount as though it were v1 succeeds and stores the
              wrong shape — which nothing notices until a reader gets an
              envelope where it expected a value.
            '';
          };
        };
      };
    }
  );

  keyType = types.submodule {
    options = {
      generator = mkOption {
        type = types.nullOr (
          types.enum [
            "base64"
            "hex"
            "alphanumeric"
            "uuid"
          ]
        );
        default = null;
        description = ''
          How `cata secrets generate` mints this key. Null means you set it by
          hand with `cata secrets edit`.

          An enum, though the CLI takes any string: an unknown generator is
          only rejected when someone runs the mint, and by then the store file
          exists and the failure looks like a tooling problem.
        '';
      };

      length = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = ''
          Entropy in bytes for `base64`, characters otherwise. Required by
          every generator but `uuid`, and capped at 4096 by the CLI.
        '';
      };
    };
  };

  managedType = types.submodule {
    options = {
      store = mkOption {
        type = types.str;
        description = "Which declared store holds this secret's keys.";
      };

      kind = mkOption {
        type = types.enum [
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

      keys = mkOption {
        type = types.attrsOf keyType;
        default = { };
        description = "The keys this secret holds.";
      };

      hostPaths = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          "ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
        };
        description = ''
          Keys to write to the host during `cata lab up`'s preflight, before
          any service starts. `$LAB_STATE_DIR` expands to the lab's state
          directory.

          A key named `*.crt` is written 0644 and everything else 0600 — the
          CLI decides on the suffix, not on `kind`, so a file that must be
          world-readable has to be named for it.
        '';
      };
    };
  };
in
{
  options.lab.secrets = {
    stores = mkOption {
      type = types.attrsOf storeType;
      default = { };
      description = "Where this lab's authored secrets live.";
    };

    managed = mkOption {
      type = types.attrsOf managedType;
      default = { };
      description = ''
        Secrets catallaxy mints or holds for you. A value a floe could
        generate for itself does not belong here — see `mkGeneratedSecret`.
      '';
    };

    envFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "examples/labs/gitops/envs/ci.env";
      description = ''
        A file a runner sources before the lab starts, for `env`-backed
        stores.

        A repository-relative path rather than a Nix path: a Nix path resolves
        into the store, which under lazy trees names something never written
        to disk, so the runner is handed a path that does not exist. The
        relative form is also what a human can act on — it is the argument to
        `git add`.

        Catallaxy never reads it. The environment is the interface; this only
        names one way to fill it.
      '';
    };

    out.hostProjections = mkOption {
      type = types.listOf types.attrs;
      internal = true;
      readOnly = true;
      description = "Flattened `<secret, key, hostPath>` triples the CLI writes during preflight.";
    };
  };

  config.lab.secrets.out.hostProjections = lib.concatLists (
    lib.mapAttrsToList (
      secretName: sec:
      lib.mapAttrsToList (key: hostPath: {
        inherit secretName key hostPath;
        inherit (sec) store kind;
      }) sec.hostPaths
    ) cfg.managed
  );

  config.lab.assertions =
    lib.mapAttrsToList (name: sec: {
      assertion = cfg.stores ? ${sec.store};
      message =
        "lab.secrets.managed.${name}.store is '${sec.store}', which is not a declared store "
        + "(${lib.concatStringsSep ", " (lib.attrNames cfg.stores)}). The store decides where the "
        + "keys live, so a name with nothing behind it has no backend to read.";
    }) cfg.managed

    # `resolve_store_or_path` treats any store argument containing `.` or `/`
    # as a filesystem path, so `cata secrets edit my.store` silently looks for
    # a file instead of the store.
    ++ lib.mapAttrsToList (name: _: {
      assertion = !(lib.hasInfix "." name) && !(lib.hasInfix "/" name);
      message =
        "lab.secrets.stores.${name}: a store name may not contain '.' or '/'. The CLI reads an "
        + "argument containing either as a path to a file, so this store could never be named on "
        + "the command line.";
    }) cfg.stores;
}
