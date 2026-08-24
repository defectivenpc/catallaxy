# The floe set this repo ships — a distro, not the platform.
#
# `modules/lab/` is the tool: typed options, the dependency graph, the
# planner, the renderers, the lint rules. It has no opinion about which
# components a cluster runs. This directory is the opinion — one set of
# choices about how Kubernetes gets built, more general than any single lab
# and less general than the platform.
#
# They are separate so that the opinion is optional. Pass your own set to
# `mkLab` and you keep the graph management and the quality gates without
# inheriting anyone else's component choices:
#
#     mkLab {
#       modules = [ ./lab.nix ];
#       floes = catallaxy.floeSets.default // {
#         cluster = removeAttrs catallaxy.floeSets.default.cluster [ "harbor" ] // {
#           mine = ./floes/mine;
#         };
#       };
#     }
#
# Two scopes, because there are two option namespaces. `cluster` floes appear
# as `floes.<name>` inside each cluster and are injected into the cluster
# submodule; `lab` floes appear as `lab.floes.<name>` and are ordinary
# top-level modules. A lab floe is the kind that stands clusters up.
{
  cluster = import ./cluster/set.nix;
  lab = import ./lab/set.nix;
}
