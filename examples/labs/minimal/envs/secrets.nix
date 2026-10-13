# The minimal lab, with material the lab holds and lands in the cluster.
#
# This is the half of the secret story a floe cannot do for itself: a value a
# human or an external system authored. A floe that wants a *random*
# credential does not come here — it mints one in its own bundle with
# `kinds.mkGeneratedSecret` and publishes the coordinates on its provide.
#
# The store is `env`-backed so the lab stands up with no key management:
# `cata secrets generate --format env` prints the exports, and the variable
# names are derived from the store, secret and key rather than declared.
# A lab someone lives in would use `sops` and commit the encrypted file.
#
# Nothing here holds a value. Every input below says where a value lives;
# `cata` reads it, decrypts it and applies the Secret itself, which is what
# keeps credentials out of the manifests, out of the digest that pins them,
# and out of the Nix store. Where each one *lands* is the cluster's to say,
# and `clusters.appWithCredentials` says it.
{
  lab,
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ../clusters.nix { inherit catallaxy floes lib; };
in
lab {
  name = "minimal.secrets";

  cluster = clusters.appWithCredentials { };

  units = {
    # The store and the secret are units of the lab's link, so the secret
    # resolves the store rather than naming it and the projection in the
    # cluster resolves the secret. With one of each there is nothing to
    # disambiguate.
    app-store = floes.lab-secret-store { backend = "env"; };

    app-credentials = floes.lab-authored-secret {
      keys = {
        # No generator: `cata secrets edit` sets it, or the environment carries
        # it. This is the "a human authored it" case.
        api-token.generator = null;

        # Minted by `cata secrets generate`, which is a different thing from a
        # floe minting its own: this value is the lab's, survives the cluster,
        # and can be projected into more than one.
        session-key = {
          generator = "base64";
          length = 32;
        };
      };
    };
  };

  # A repository-relative path, not a Nix path: a Nix path resolves into the
  # store, which under lazy trees names something never written to disk. It is
  # also what makes this lab stand up unattended — without it
  # `selfContained` reports the values as unreachable and the e2e runner skips
  # it.
  secretsEnvFile = "examples/labs/minimal/envs/secrets.env";
}
