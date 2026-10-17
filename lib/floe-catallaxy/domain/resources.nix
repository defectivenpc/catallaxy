# The `resources` delivery category.
{ lib, floe }:

let
  T = floe.T;

  phases = [
    "before-clusters"
    "after-clusters"
  ];

  resourceSchema = T.named "resource" (
    T.record {
      provider = T.str;
      type = T.str;

      inputs = T.attrsOf T.any;

      outputs = T.listOf T.str;

      phase = T.enum phases;
    }
  );

  publicationSchema = T.named "publication" (
    T.record {
      resource = T.str;
      output = T.str;

      store = T.str;
      key = T.str;
    }
  );
in
{
  inherit phases;

  resources = floe.mkSig {
    name = "catallaxy.resources";
    canonicalName = "resources";
    description = "Infrastructure declared for a state-based tool to create, for the case no cluster can own it.";
    fields = T.attrsOf resourceSchema;
  };

  publications = floe.mkSig {
    name = "catallaxy.publications";
    canonicalName = "publications";
    description = "Where a resource's output lands once it exists, as an address in a lab secret store.";
    fields = T.attrsOf publicationSchema;
  };
}
