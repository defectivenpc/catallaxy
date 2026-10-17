/*
  The Kubernetes API a cluster serves: resolve a resource's type, or ask
  whether a kind is built in.

      mkApi { inherit floeCore specFile; crdGroups = floeCrds.groups; }
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
  floeCore,

  # The pinned OpenAPI spec, as a path. Converted here rather than generated
  # into Nix: `fromJSON` on 3.1 MB costs 35 ms, where the 77,623 lines of
  # generated Nix this replaced cost 82 ms just to parse.
  specFile,

  # API group -> the group's schemas, from `lib/floe-crds.nix`.
  #
  # Required, with no default. `{ }` is a legal and useful answer — it means
  # "the Kubernetes API only", which is all `coreKinds` needs — but a *default*
  # of it would hand a caller a lookup table silently missing every CRD, and
  # `conform.nix` resolving a custom resource against that finds no schema and
  # checks none of its fields. One call site asked for it by accident and the
  # coverage check reported every CRD in the tree as unschema'd.
  crdGroups,
}:

import ./schema-to-type.nix
  {
    inherit lib;
    T = floeCore.T;
  }
  {
    spec = builtins.fromJSON (builtins.readFile specFile);
    inherit crdGroups;
  }
