# The `resources` delivery category — RFC 0003.
#
# The state-based camp: declare, diff against recorded state, apply once,
# record what was made. The reconcile camp (bundles) is what every other floe
# in this tree emits, and the two cannot be dissolved into each other for one
# blunt reason — something has to create the cluster the controllers run in.
#
# What a floe writes here names no tool. `provider` and `type` are the
# Terraform registry's vocabulary, which is a borrowed *namespace* rather than
# a borrowed implementation: OpenTofu reads the same registry, and RFC 0003 §9
# records that pretending otherwise would mean maintaining a translation table
# for every provider in existence.
{ lib, floe }:

let
  T = floe.T;

  # Three positions relative to cluster lifecycle. `after-manifests` is
  # deliberately absent: RFC 0003 §11 doubts it earns its place, the only
  # concrete case it named was a DNS record for a running service, and
  # external-dns already does that from inside the cluster in the other camp.
  # A phase nothing uses is a phase nothing tests.
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

    # Declared, never inferred (RFC 0003 §3). A typo in a consumer's
    # reference then fails at evaluation naming the resource and the output,
    # rather than part-way through an apply that has already created things.
    outputs = T.listOf T.str;

    phase = T.enum phases;
  };

  # Where an output goes once it exists.
  #
  # RFC 0003 §7 calls this a publication and warns it is the easiest thing in
  # the design to get wrong: the tempting shape sends outputs to some external
  # store and lets the cluster fetch them back, which quietly introduces a
  # second addressing scheme understood by neither side.
  #
  # So there is no second scheme. A publication writes into a lab secret store
  # the lab already declares, and a cluster reads it with the
  # `secrets.subscribe` it already has. The value exists on the operator's
  # host for the length of one apply and is handed straight on.
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
    schema = T.attrsOf resourceSchema;
  };

  publications = floe.mkOutputKind {
    name = "catallaxy.publications";
    schema = T.attrsOf publicationSchema;
  };
}
