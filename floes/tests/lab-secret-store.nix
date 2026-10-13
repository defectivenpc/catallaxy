# lab-secret-store, alone.
#
# Nothing here holds a value, so what is worth pinning is the one thing the
# floe decides rather than carries: whether a cluster may write into the
# store. That follows from the backend and was a hand-set flag on two
# different floes, either of which could disagree with it.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  storeWith =
    inputs:
    support.evalFloe {
      name = "lab-secret-store";
      inherit inputs;
    };

  recordOf = r: r.link.provides.lab-secret-store.labStore;
in
lib.runTests {

  # `sops` and `env` are read-only and top-down: you write the value, `cata`
  # decrypts it at deploy and projects it into every cluster that needs it. A
  # cluster cannot write back — for `sops` that would mean committing to your
  # repository. The other two are writable, which is what decides whether a
  # value one cluster minted can travel to another at all.
  #
  # Derived from the backend rather than declared, so the two cannot disagree.
  # `direction` is the same fact worded for the CLI and `lab-secrets` derives
  # it; the suite for that floe is where it is pinned, because this one is not
  # where it is decided.
  testWritabilityIsDerivedFromTheBackend = {
    expr =
      map
        (backend: {
          inherit backend;
          inherit
            (recordOf (storeWith {
              inherit backend;
            }))
            writable
            ;
        })
        [
          "sops"
          "env"
          "vault"
          "external"
        ];
    expected = [
      {
        backend = "sops";
        writable = false;
      }
      {
        backend = "env";
        writable = false;
      }
      {
        backend = "vault";
        writable = true;
      }
      {
        backend = "external";
        writable = true;
      }
    ];
  };

  # The name a consumer resolves is the unit name, because that is what
  # `cata secrets edit <store>` takes. Nothing declares it.
  testItsNameIsItsUnitName = {
    expr = (storeWith { backend = "sops"; }).provides.labStore.name;
    expected = "lab-secret-store";
  };

  # The vault block is carried flat as inputs and nested on the provide,
  # because the inputs are what a lab writes and `SecretStoreSpec` is what the
  # CLI parses. A `v2` mount written as though it were `v1` succeeds and
  # stores the wrong shape, which nothing notices until a reader gets an
  # envelope where it expected a value.
  testTheVaultCoordinatesReachTheRecord = {
    expr =
      (recordOf (storeWith {
        backend = "vault";
        vaultServer = "https://bao.example.test";
        vaultPath = "lab";
        vaultVersion = "v1";
      })).vault;
    expected = {
      server = "https://bao.example.test";
      path = "lab";
      version = "v1";
    };
  };

  # Null server, for a store whose address nothing here states. It was meant
  # to be filled from whatever a cluster provided `VAULT_SERVER`, and nothing
  # ever did; a routed name is what `cata` dials from the host, so a lab that
  # needs one sets it.
  testItLeavesAnUnsetVaultServerNull = {
    expr =
      (recordOf (storeWith {
        backend = "vault";
      })).vault.server;
    expected = null;
  };

  # What makes the backend set open. Each gets `CATA_SECRET_KEY` in the
  # environment and the value on stdin, so a value never reaches a process
  # listing.
  testTheWriterAndRemoverAreCarried = {
    expr =
      let
        rec' = recordOf (storeWith {
          backend = "external";
          writerCommand = [ "vault-put" ];
          removerCommand = [ "vault-delete" ];
        });
      in
      {
        inherit (rec') writerCommand removerCommand;
      };
    expected = {
      writerCommand = [ "vault-put" ];
      removerCommand = [ "vault-delete" ];
    };
  };

  # A store with no remover is not an error: destroying a stack says what it
  # could not take back rather than refusing to finish.
  testAStoreNeedsNoRemover = {
    expr =
      (recordOf (storeWith {
        backend = "external";
      })).removerCommand;
    expected = null;
  };
}
