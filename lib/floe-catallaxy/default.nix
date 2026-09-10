# The Catallaxy distribution over floe core: the output kinds it registers,
# the signatures its floes speak, the policies it enforces at link, the fold
# from a link result to a cluster picture, and the renderer over that.
{ lib, pkgs }:

let
  # Core plus this domain's own types; see ./prelude.nix.
  floe = import ./prelude.nix { inherit lib; };

  kinds = import ./kinds.nix { inherit lib floe; };
  sigs = import ./sigs.nix { inherit floe; };
in
{
  inherit floe kinds sigs;

  mkComponentFloe =
    args:
    floe.mkFloe (
      args
      // {
        requires = {
          cluster = sigs.KUBERNETES_CLUSTER;
        }
        // (args.requires or { });

        out = {
          component = kinds.component;
        }
        // (args.out or { });
      }
    );

  policies = import ./policies.nix { inherit lib; };

  inherit (import ./elaborate.nix { inherit lib; }) elaborateCluster;
  inherit (import ./render.nix { inherit lib pkgs; }) renderCluster;
}
