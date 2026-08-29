# The lab-scope platform floes this repo ships.
#
# Separate from the cluster-scope set because they land in a different option
# namespace: these are built with `labFloeOptions` and appear under
# `lab.floes.<name>`, while the cluster set appears under `floes.<name>` inside
# each cluster.
#
# Nothing here confers platform-hood. A floe becomes a platform by exporting
# `clusters`, checked structurally in ./default.nix, so a floe written outside
# this repo is treated the same. This list only says which ones ship in the
# box.
{
  k3d-local = ./k3d-local.nix;
  talos-local = ./talos-local.nix;
}
