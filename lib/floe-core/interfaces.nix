# Signatures and output kinds. Both are pure data.
{ lib }:

{
  # A signature: a named record schema over data.
  # fields :: attrset of floe types (see types.nix).
  mkSig = { name, fields }: {
    __floeSig = true;
    inherit name fields;
  };

  # An output kind: a registered dotted name plus a schema for one class of
  # build product. Kinds are defined by distributions, not floe core.
  mkOutputKind = { name, schema }: {
    __floeKind = true;
    inherit name schema;
  };
}
