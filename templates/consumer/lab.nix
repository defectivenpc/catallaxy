# Your topology.
#
# A lab is a floe, so this is a floe definition: it declares what its
# environments may vary and places the units and clusters it holds. The
# cluster's own composition is in `clusters.nix`, where its header states its
# interface.
#
# Three sets of floes reach it as ordinary arguments, because a floe is a
# function rather than a module to import. `floes` is catallaxy's set and
# `catallaxy` the distribution — both handed in by the flake from
# `cata.floes` and `cata.catallaxy` — and `myFloes` is yours.
{
  lib,
  floes,
  catallaxy,
  myFloes,
}:

let
  clusters = import ./clusters.nix {
    inherit
      catallaxy
      floes
      myFloes
      lib
      ;
  };
in
catallaxy.mkLabFloe {
  name = "my-platform";
  summary = "One cluster, and the floes you wrote in it.";

  inputs = {
    zone.default = "example.test";

    claim = lib.mkOption {
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
        inherit (inputs) claim;
      };
    };
}
