{ lib, floe }:

lib.foldl' lib.attrsets.unionOfDisjoint { } (
  map (family: import family { inherit lib floe; }) [
    ./cluster.nix
    ./lab.nix
    ./routing.nix
    ./tls.nix
    ./secrets.nix
    ./services.nix
    ./observability.nix
  ]
)
