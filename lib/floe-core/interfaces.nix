# Signatures and output kinds. Both are pure data.
{ lib }:

{
  # A signature: a named record schema over data.
  # fields :: attrset of floe types (see types.nix).
  # A signature is a record type, and that is all it is.
  #
  # There was briefly a `crossCluster` boolean here saying whether the promise
  # travelled to another link. It was wrong three ways: it named a Kubernetes
  # concept in a layer whose premise is that it has none, it sat beside
  # `fields` as a second kind of thing in what is otherwise a type, and it
  # measured a per-field property at signature granularity — every signature
  # in the distribution is a mix, so the claim was false in both directions.
  # `T.local` on the fields says it where it is true.
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
