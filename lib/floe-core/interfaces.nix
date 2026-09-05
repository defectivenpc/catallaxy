# Signatures and output kinds. Both are pure data.
{ lib }:

{
  # A signature: a named record schema over data.
  # fields :: attrset of floe types (see types.nix).
  mkSig =
    {
      name,
      fields,

      # Whether this promise still means something to a consumer in a
      # different link.
      #
      # Most do not, and the default says so. A signature like "the
      # external-secrets controller is running" or "the admission webhook is
      # accepting" is a statement about *this* graph: resolving it from
      # another one produces a value that reads fine and describes a
      # controller that is not there. That failure has no symptom until a
      # resource sits unreconciled.
      #
      # A signature that does cross carries an address a stranger can reach —
      # a routed URL, a registry, an issuer — and says so here. `link` refuses
      # an external provide of a signature that has not, which is the one
      # thing it can check: it cannot see which field a consumer will read,
      # but it can see whether the promise was ever meant to travel.
      crossCluster ? false,
    }:
    {
      __floeSig = true;
      inherit name fields crossCluster;
    };

  # An output kind: a registered dotted name plus a schema for one class of
  # build product. Kinds are defined by distributions, not floe core.
  mkOutputKind = { name, schema }: {
    __floeKind = true;
    inherit name schema;
  };
}
