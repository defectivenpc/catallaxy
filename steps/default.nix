{ lib }:

let
  tokens = import ./tokens.nix { inherit lib; };
  kinds = import ./kinds.nix { inherit lib; };
in
{
  inherit tokens kinds;

  types = import ./types.nix {
    inherit lib;
    planTokens = tokens;
    stepKinds = kinds;
  };
}
