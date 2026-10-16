# The minimal lab as it runs by default: audited, and with Pod Security on.
#
# An environment is an instantiation, so this is `lab.nix`'s defaults with two
# of its inputs answered.
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
  name = "minimal.local";

  # The one lab that enforces Pod Security Admission, so the labels are
  # applied somewhere rather than only rendered. `podinfo` is held to
  # `restricted` because it already satisfies it, which is the up direction of
  # the override reading both ways.
  #
  # Re-instantiated rather than set beside the cluster, because what a cluster
  # asks of every namespace in it is the cluster's own declaration — the same
  # reason the claim below is an instantiation and not a flag.
  cluster = clusters.app {
    podSecurity = {
      enable = true;
      override.podinfo = "restricted";
    };
  };

  provisioner = floes.k3d-cluster { auditLogging.enable = true; };
}
