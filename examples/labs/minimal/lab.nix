# One cluster, a platform, and one service behind it.
#
# The whole of what a lab author writes: which cluster floes are placed, what
# brings each one into existence, and the host services around them. The
# cluster's own composition is in `clusters.nix`, where its header states the
# interface; ordering is nowhere, because nothing declares it — the linker
# resolves the signatures and the elaborator derives the install order.
#
# A floe, so the two things its five environments swap are declared inputs with
# defaults, and `envs/*.nix` are instantiations. What differs between
# `minimal.local` and `minimal.tls` is readable here rather than by merging
# five files.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters.nix { inherit catallaxy floes lib; };
in
catallaxy.mkLabFloe {
  name = "minimal";
  summary = "One cluster, a platform, and one service behind it.";

  inputs = {
    zone.default = "minimal.test";

    # The base lab runs no ingress, so podinfo's route is genuinely unreachable
    # from the host and the endpoint probe is right to say so. `minimal.tls`
    # stands one up and turns this back on; the probe is off here rather than
    # worked around, because a lab publishing no ingress port has nothing to
    # dial.
    verifyEndpoints.default.enable = false;

    cluster = lib.mkOption {
      type = catallaxy.floeInstance;
      default = clusters.app { };
      defaultText = lib.literalExpression "clusters.app { }";
      description = ''
        The one cluster this lab stands up.

        An instance and not a flag, which is what lets an environment be a
        different cluster rather than the same one with a branch in it:
        `minimal.cilium` passes `clusters.appWithCilium`, and `minimal.secrets`
        a cluster that projects lab-held credentials. Both include
        `clusters.app` rather than copying it.
      '';
    };

    claim = lib.mkOption {
      type = catallaxy.floeInstance;
      default = floes.k3d-cluster { };
      defaultText = lib.literalExpression "floes.k3d-cluster { }";
      description = ''
        What brings that cluster into existence.

        Beside the cluster rather than inside it, and that is the whole point:
        `minimal.talos` swaps the provisioner without touching a component,
        because the components resolve against the hole this fills rather than
        against the thing that fills it.
      '';
    };
  };

  units = _: {
    # The cache survives `lab destroy`, so standing this lab back up pulls from
    # disk rather than from the internet. `minimal.talos` withdraws it.
    registry = floes.lab-registry { };
  };

  clusters =
    { inputs, ... }:
    {
      app = {
        floe = inputs.cluster;
        inherit (inputs) claim;
      };
    };
}
