# Two clusters sharing a secret through a runtime store.
#
# The chain, end to end, is the point:
#
#   an authored store holds the credential for the runtime store
#     -> projected into each cluster as the token its ClusterSecretStore uses
#       -> `core` mints a CA and publishes it
#         -> `obs` subscribes and materialises it under its own name
#
# Neither cluster reads the other's configuration. `core` derives the address
# from its own identity; `obs` derives the same string from the cluster it
# names. Nothing is negotiated, so nothing can cycle and `core` never learns
# who reads it.
#
# It renders and is checked like any lab and never enters the e2e set: it
# needs a vault, which a fixture has no business standing up. What it pins is
# that the two sides agree, which is exactly the half that has no runtime
# symptom short of an ExternalSecret waiting forever.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  zone = "secret-sharing.test";
  vaultServer = "https://vault.${zone}";

  clusters = import ./clusters/secret-sharing.nix {
    inherit
      catallaxy
      floes
      lib
      vaultServer
      ;
  };
in
catallaxy.mkLabFloe
  {
    name = "secret-sharing";
    summary = "Two clusters sharing a secret through a runtime store.";

    units = _: {
      # Two stores: one a human authored, one the lab writes into at runtime.
      # Both are units of the link, so with two of them every reader says which
      # it means.
      authored = floes.lab-secret-store { backend = "sops"; };

      runtime = floes.lab-secret-store {
        backend = "vault";
        inherit vaultServer;
      };

      vault-credential =
        (floes.lab-authored-secret {
          keys.token.generator = "hex";
          keys.token.length = 32;
        }).bind
          { labStore = "authored"; };
    };

    # An address plan written down, because two clusters share one network and
    # deriving the ranges from a name would silently move one on a rename.
    clusters = _: {
      core = {
        floe = (clusters.core { }).bind { labStore = "runtime"; };
        claim = floes.k3d-cluster {
          podSubnet = "10.244.0.0/16";
          serviceSubnet = "10.96.0.0/12";
        };
      };

      obs = {
        floe = (clusters.obs { }).bind { labStore = "runtime"; };
        claim = floes.k3d-cluster {
          podSubnet = "10.245.0.0/16";
          serviceSubnet = "10.112.0.0/12";
        };
      };
    };
  }
  {
    name = "secret-sharing";
    inherit zone;
  }
