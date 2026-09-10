# The `resources` delivery category — RFC 0003.
{ lib, floe }:

let
  T = floe.T;

  phases = [
    "before-clusters"
    "after-clusters"
  ];

  resourceSchema = T.record {
    # Which provider reconciles it, and the type in that provider's
    # vocabulary. Both are registry names, not tool names.
    provider = T.str;
    type = T.str;

    # Its configuration. May hold deferred tokens, which is what makes an
    # ordering edge between stacks — see `lib/render/infra.nix`.
    inputs = T.attrsOf T.any;

    outputs = T.listOf T.str;

    phase = T.enum phases;
  };

  publicationSchema = T.record {
    # The resource, and which of its declared outputs.
    resource = T.str;
    output = T.str;

    # Where it lands: an entry in `lab.secrets.stores`, and a key in it.
    store = T.str;
    key = T.str;
  };
in
{
  inherit phases;

  resources = floe.mkOutputKind {
    name = "catallaxy.resources";
    description = "Infrastructure declared for a state-based tool to create, for the case no cluster can own it.";
    schema = T.attrsOf resourceSchema;
  };

  publications = floe.mkOutputKind {
    name = "catallaxy.publications";
    description = "Where a resource's output lands once it exists, as an address in a lab secret store.";
    schema = T.attrsOf publicationSchema;
  };
}
