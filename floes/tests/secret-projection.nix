# secret-projection, alone.
#
# Two claims. The declaration reaches the document, so `cata` knows which
# store entry fills which Secret; and the bundle holds the position with no
# resources, so whatever reads the Secret waits for it without knowing the
# CLI is what supplies it.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  projectionOf =
    keys:
    support.evalFloe {
      name = "secret-projection";
      inputs = {
        secret = "vault-token";
        namespace = "external-secrets";
        inherit keys;
      };
    };

  r = projectionOf { token.from = "token"; };
in
lib.runTests {

  # Keyed by the Secret's name, because `cata` renders `metadata.name` from
  # the key: a field for it would be one the CLI ignores.
  testTheDeclarationIsKeyedByTheSecretsName = {
    expr = r.link.out."catallaxy.projections".secret-projection;
    expected = {
      vault-token = {
        source = "stub-labSecret";
        namespace = "external-secrets";
        keys.token = {
          from = "token";
          transform = null;
          jsonKey = null;
        };
      };
    };
  };

  # Which authored secret supplies the values is resolved, so the name in the
  # declaration is the one the link found rather than a string written here.
  # It was `source = "<name>"` naming an attribute under
  # `lab.secrets.managed`, and a typo left a Secret `cata` had no values for
  # while whatever mounted it waited forever.
  testItsSourceIsTheSecretItResolved = {
    expr = r.link.out."catallaxy.projections".secret-projection.vault-token.source;
    expected = "stub-labSecret";
  };

  # And a key the resolved secret does not hold is refused here, where the
  # projection is written — not at `cata lab up`, when the store turns out to
  # have nothing under it.
  testReadingAKeyTheSecretDoesNotHoldIsRefused = {
    expr =
      (builtins.tryEval (
        builtins.deepSeq (projectionOf { token.from = "not-a-key"; }).link.out."catallaxy.projections"
          "evaluated"
      )).success;
    expected = false;
  };

  # The position, and nothing else. A resource here would be a secret in the
  # store path, which is the whole thing this avoids.
  testItHoldsThePositionAndRendersNothing = {
    expr = {
      inherit (r.bundles.projection) secrets resources;
    };
    expected = {
      secrets = [ "external-secrets/vault-token" ];
      resources = { };
    };
  };
}
