{
  lib,
  floe,
  sigs,
}:

lib.foldl' lib.attrsets.unionOfDisjoint { } (
  map (family: import family { inherit lib floe sigs; }) [
    ./component.nix
    ./cluster.nix
    ./lab.nix
    ./resources.nix
  ]
)
