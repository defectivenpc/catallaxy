# Writing an anchor. `lib/eval/graph.nix` reads them.
#
# A hard anchor that matches nothing is an error; an `optional:` one matches
# nothing silently, which is why `wants` is the riskier of the two.
{ }:

{
  # needs :: Token -> Anchor — must be provided, or eval fails.
  needs = token: "provides:${token}";

  # wants :: Token -> Anchor — order against it if it exists.
  wants = token: "optional:provides:${token}";

  wantsAll = tokens: map (token: "optional:provides:${token}") tokens;

  wantsKind = kind: "optional:kind:${kind}";
}
