# Your topology.
#
# A lab is a floe, so this is a floe definition: it declares what its
# environments may vary and places the units and clusters it holds. The
# cluster's own composition is in `clusters.nix`, where its header states its
# interface.
#
# Both reach it as ordinary arguments, because a floe is a function rather
# than a module to import. `floes` is every floe there is — catallaxy's and
# yours in one namespace — and `catallaxy` is the distribution. The flake
# hands in both from `cata`, which it built with `withFloes`.
{
  lib,
  floes,
  catallaxy,
}:

let
  clusters = import ./clusters.nix {
    inherit
      catallaxy
      floes
      lib
      ;
  };
in
catallaxy.mkLabFloe {
  name = "my-platform";
  summary = "One cluster, and the floes you wrote in it.";

  inputs = {
    zone.default = "example.test";

    provisioner = lib.mkOption {
      type = catallaxy.floeInstance;
      default = floes.k3d-cluster { };
      defaultText = lib.literalExpression "floes.k3d-cluster { }";
      description = ''
        What establishes the claim the cluster leaves open. Beside the cluster
        and not inside it, so an environment swaps the provisioner — k3d here,
        Talos or a managed cluster elsewhere — without touching a component.
      '';
    };
  };

  clusters =
    { inputs, ... }:
    {
      app = {
        floe = clusters.app { };
        inherit (inputs) provisioner;
      };
    };
}
