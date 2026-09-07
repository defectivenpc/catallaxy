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

  # A floe that installs into a cluster and emits a component.
  #
  # Every one of the 31 such floes wrote the same two lines —
  # `requires.cluster = sigs.KUBERNETES_CLUSTER` in 33 of 33 and
  # `out.component = kinds.component` in 31 of 33 — so between them they
  # carried no information and cost every reader two lines to confirm were
  # the constant lines. The wrapper *is* the type: it names a kind of thing,
  # and the block below it shows only what differs.
  #
  # The rule this follows, so the next constant is decided the same way:
  # default a constant when it is plumbing, keep it explicit when a check
  # reads it as the author's claim. These two are plumbing —
  # `componentsTargetTheCluster` verifies the wiring exists, it does not
  # believe the author about anything. `imagesComplete` is a claim
  # `floe-gates.nix` believes, so it stays written out even at 31 of 33.
  #
  # Transparent to every consumer: `lib/lab.nix`, `floes/tests/support.nix`,
  # `nix/checks/floe-gates.nix` and `modules/lab/cd.nix` all read the
  # returned `def`, never the source text.
  mkComponentFloe =
    args:
    floe.mkFloe (
      args
      // {
        # Merged over, not replaced: a floe that requires a gateway as well
        # keeps both, and one that genuinely needs a second cluster hole can
        # still name it.
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
