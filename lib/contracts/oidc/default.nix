{ lib }:

{
  inherit (import ./scopes.nix { inherit lib; }) mkScopeAssertion scopeAssertion;
  inherit (import ./client.nix { inherit lib; })
    secretRefType
    clientOptions
    clientsType
    nullableClient
    ;
}
