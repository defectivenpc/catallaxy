# A minimal cluster. Outlining how to define a lab, a cluster, and a service that runs in the cluster
#
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

    provisioner = lib.mkOption {
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
    registry = floes.lab-registry { };
  };

  clusters =
    { inputs, ... }:
    {
      app = {
        floe = inputs.cluster;
        inherit (inputs) provisioner;
      };
    };
}
