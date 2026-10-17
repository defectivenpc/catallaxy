/*
  The Kubernetes API a cluster serves: resolve a resource's type, or ask
  whether a kind is built in.

      mkApi { crdGroups = floeCrds.groups; }
      -> { resolve; coreKinds; }

  The two questions anything asks of the API, and the only two. Threaded as
  one record rather than as the table it is built from, so what a consumer
  gets is an answer and not a lookup it has to assemble — `conform.nix` used
  to reach `generatedTypes.resolveResourceType typesByKind`, which is three
  names to say one thing, repeated at every call site.

  It is also the seam where the API's *source* is chosen. Everything above
  here asks `resolve` and `coreKinds`; what answers them is this file's
  business alone.
*/
{
  lib,

  # API group -> the group's generated types, from `lib/floe-crds.nix`.
  #
  # Required, with no default. `{ }` is a legal and useful answer — it means
  # "the Kubernetes API only", which is all `coreKinds` needs — but a *default*
  # of it would hand a caller a lookup table silently missing every CRD, and
  # `conform.nix` resolving a custom resource against that finds no schema and
  # checks none of its fields. One call site asked for it by accident and the
  # coverage check reported every CRD in the tree as unschema'd.
  crdTypes,

  k8sVersion ? "1.31",
}:

let
  types = import ./types.nix { inherit lib crdTypes k8sVersion; };
in
{
  /*
    The type for an apiVersion and kind, or null when nothing describes it.

        resolve "apps/v1" "Deployment"   # => a type
        resolve "nope.io/v1" "X"         # => null
  */
  resolve = types.generatedTypes.resolveResourceType types.typesByKind;

  # The kinds an apiserver has without anyone installing a CRD, as a set for
  # membership testing. 141 of them at 1.31.
  inherit (types) coreKinds;
}
