# Signatures and output kinds. Both are pure data.
{ lib, types }:

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
  # `as` and `description` are required, not optional. An optional
  # documentation field is one half the set omits — this tree has 206
  # `mkOption`s and voluntary descriptions, and the coverage shows it. Making
  # them mandatory is what makes the derived interface document complete by
  # construction rather than complete where someone remembered.
  #
  # `as` is the canonical local name a hole or promise binds this signature
  # under. Before it, `provides.operator` bound four different signatures and
  # `GATEWAY_API` was `api` on its provider and `gatewayApi` on both its
  # consumers — so a reader could not tell what a hole was for without
  # following it. `nix/checks/floe-names.nix` enforces the bijection.
  # Defaulted to null and then refused, rather than left out of the pattern:
  # the pattern stays closed, so an unknown key is still an error, and the
  # message a floe author gets says what the field is for instead of Nix's
  # "called without required argument".
  mkSig =
    {
      name,
      as ? null,
      description ? null,
      fields,
    }:
    if as == null then
      throw (
        "signature '${name}': needs `as`, the canonical name a hole or promise binds it under. "
        + "Without one, `provides.operator` can mean four different signatures and a reader "
        + "cannot tell which — which is what it meant before this was required."
      )
    else if description == null then
      throw (
        "signature '${name}': needs a one-line `description`. It is what the generated "
        + "interface document says a hole is for, and a comment in this file reaches nothing."
      )
    else
      {
        __floeSig = true;
        inherit
          name
          as
          description
          fields
          ;
      };

  # Whether a promise of this signature could mean anything in another link.
  #
  # Derived from the fields rather than declared beside them, so a signature
  # that gains a routed address starts crossing without anyone remembering to
  # say so. `link` refuses such an entry in its scope, and a container that
  # assembles scopes should refuse the *offer* — which is where whoever wrote
  # it can do something about it, and is reachable even when no second link
  # exists yet to be handed one.
  isUncrossable = sig: lib.all (t: types.isLocal t) (lib.attrValues sig.fields);

  # A floe's input declarations, rendered as data.
  #
  # The declaration and not the supplied value: the value is a deployer's
  # choice and belongs to whatever instantiated the floe, while the type,
  # default and description are the floe's own contract and are the same
  # wherever it is instantiated.
  #
  # Lives here rather than in `link` because two things want it — the link
  # result (RFC 0001 §216) and the generated interface document — and two
  # renderings of one thing disagree.
  renderInputs = lib.mapAttrs (
    _: opt: {
      type = opt.type.description or "unknown";

      # `defaultText` when the author wrote one: a default computed from
      # another option otherwise renders as a store path or a function, which
      # tells a reader nothing about what they may leave out.
      default =
        if opt ? defaultText then
          opt.defaultText.text or opt.defaultText
        else if opt ? default then
          builtins.toJSON opt.default
        else
          null;

      description = opt.description or "";
    }
  );

  # An output kind: a registered dotted name plus a schema for one class of
  # build product. Kinds are defined by distributions, not floe core.
  mkOutputKind =
    {
      name,
      description ? null,
      schema,
    }:
    if description == null then
      throw "output kind '${name}': needs a one-line `description` saying what it carries."
    else
      {
        __floeKind = true;
        inherit name description schema;
      };
}
