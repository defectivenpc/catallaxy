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
# Nothing here holds a value. Every option below says where a value lives;
# `cata` reads it, decrypts it and applies the Secret itself, which is what
# keeps credentials out of the manifests, out of the digest that pins them,
# and out of the Nix store.
{
  lib,
  floes,
  config,
  ...
}:
{
  lab.name = "minimal.secrets";

  # Its own subnet and ports, so it can be up beside the other two.
  lab.network.subnet = "172.26.0.0/16";
  lab.registry.port = 5052;

  lab.secrets.stores.app.backend = "env";

  # A repository-relative path, not a Nix path: a Nix path resolves into the
  # store, which under lazy trees names something never written to disk. It is
  # also what makes this lab stand up unattended — without it `lab.out.selfContained`
  # reports the values as unreachable and the e2e runner skips it.
  lab.secrets.envFile = "examples/labs/minimal/envs/secrets.env";

  lab.secrets.managed.app-credentials = {
    store = "app";
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

  lab.clusters.app = {
    # `podinfo` is the namespace anything here would consume it from.
    secrets.project.app-credentials = {
      source = "app-credentials";
      namespace = "podinfo";
      keys = {
        token.from = "api-token";
        session.from = "session-key";
      };
    };

    floes.cluster = lib.mkForce (
      floes.k3d-cluster {
        name = "app";
        instanceName = "minimal-secrets-app";
      }
    );
  };
}
