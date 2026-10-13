# lab-authored-secret, alone.
#
# It holds no value, so what is worth pinning is what it *says it holds*: the
# key list a projection resolves against. A `ca` secret carries two keys
# nobody declared, and a host path for a key the secret does not hold would
# have the preflight write nothing while every service mounting that path
# started against a file which is not there.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  secretWith =
    inputs:
    support.evalFloe {
      name = "lab-authored-secret";
      inherit inputs;
    };

  recordOf = r: r.link.provides.lab-authored-secret.labSecret;
in
lib.runTests {

  # Which store backs it is resolved, not spelled. It was `store = "<name>"`
  # under `lab.secrets.managed`, guarded by an assertion comparing the string
  # against the declared stores — which is resolution, written out by hand.
  testItsStoreIsResolved = {
    expr = (recordOf (secretWith { })).store;
    expected = "stub-labStore";
  };

  # The name a projection resolves is the unit name, because that is what
  # `cata secrets edit <store> <secret>` takes.
  testItsNameIsItsUnitName = {
    expr = (secretWith { }).provides.labSecret.name;
    expected = "lab-authored-secret";
  };

  # What a projection may read, so one naming a key this does not hold is
  # refused where the projection is written rather than at `cata lab up`.
  # `readableKeys` and not `keys`: the second is what `cata` *generates*, and a
  # `ca` secret is readable at two keys it declares neither of.
  testItPublishesTheKeysItHolds = {
    expr =
      (secretWith {
        keys = {
          token.generator = "hex";
          api-token.generator = null;
        };
      }).provides.labSecret.readableKeys;
    expected = [
      "api-token"
      "token"
    ];
  };

  # A `ca` secret carries `ca.crt` and `ca.key` whether or not anyone declared
  # them — together, because the certificate is signed by that key and
  # generating them separately does not compose. So a projection reading
  # `ca.crt` resolves against what the CLI will actually write.
  testACaSecretHoldsItsPairWithoutDeclaringIt = {
    expr = (secretWith { kind = "ca"; }).provides.labSecret.readableKeys;
    expected = [
      "ca.crt"
      "ca.key"
    ];
  };

  # How `cata secrets generate` mints each one, carried verbatim. Null is the
  # "a human authored it" case: `cata secrets edit` sets it, or the
  # environment carries it.
  testTheGeneratorsReachTheRecord = {
    expr =
      (recordOf (secretWith {
        keys = {
          token = {
            generator = "base64";
            length = 32;
          };
          authored.generator = null;
        };
      })).keys;
    expected = {
      token = {
        generator = "base64";
        length = 32;
      };
      authored = {
        generator = null;
        length = null;
      };
    };
  };

  # A key named `*.crt` is written 0644 and everything else 0600 — the CLI
  # decides on the suffix, not on `kind`, so the path is carried as written.
  testHostPathsReachTheRecord = {
    expr =
      (recordOf (secretWith {
        kind = "ca";
        hostPaths."ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
      })).hostPaths;
    expected = {
      "ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
    };
  };

  # And a host path for a key the secret does not hold is refused. The
  # preflight would write nothing, and the failure would surface as a service
  # starting against a file that is not there — one layer away from the cause.
  testAHostPathForAKeyItDoesNotHoldIsRefused = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq (recordOf (secretWith {
          hostPaths."ca.crt" = "$LAB_STATE_DIR/proxy/ca.crt";
        })) "evaluated"
      )).success;
    expected = false;
  };
}
