# The artifact this floe's CRD types are generated from.
#
# The *same* pinned thing the floe installs, so the types describe the CRDs
# that will actually be applied. Generating from a separately pinned copy is
# how types come to describe a Kubernetes nobody is running.
#
# This file existing is what says "generate types for this floe". There is no
# list: `floes/crds.nix` finds every floe carrying one, and `crds/<group>.nix`
# beside it is the output.
{ cataCharts, ... }:

cataCharts.redis-operator.crds
