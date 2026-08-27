# Floe core: mixin linking over `lib.evalModules` (RFC 0001). Contains no
# Kubernetes — signatures, kinds and policies belong to a distribution.
#
#   floe = import ./lib/floe-core { inherit lib; };   # lib = nixpkgs lib
{ lib }:

let
  types = import ./types.nix { inherit lib; };
  interfaces = import ./interfaces.nix { inherit lib; };
  floe = import ./floe.nix { inherit lib types; };
  link = import ./link.nix {
    inherit lib types;
    floeLib = floe;
  };
in
{
  T = types;
  inherit (types) checkValue isDeferredToken;
  inherit (interfaces) mkSig mkOutputKind;
  inherit (floe) mkFloe;
  inherit (link) link;
}
