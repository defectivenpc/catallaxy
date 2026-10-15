/*
  Which floes in a set have typed CRDs, and the types themselves.

      floeCrds { floeSet = import ./floes; }
      -> { sources = { cert-manager = <fn>; … };
           types   = { "cert-manager.io" = <path>; … }; }

  Derived, not listed. A floe whose `upstream.nix` yields a `crds` attribute is
  a floe whose CRDs get Nix types, and `crds/<group>.nix` beside it is the
  output — so adding one needs no central edit, and deleting a floe deletes its
  types with it.

  Takes the floe set rather than reading `floes/` directly, which is what lets
  a floe outside this repository contribute types. The built-in set is not
  special: it is the set catallaxy ships, collected by this same function.

  Two readers, which is why this is one expression. `sources` is what the
  generator reads; `types` is what conformance resolves against. A group
  appearing in one and not the other means the committed types are stale, which
  is what `generated-types` compares.

  Evaluates no floe. It reads paths and applies `upstream.nix`, nothing more —
  it has to, because `crdTypes` is what the distribution record is built from
  and a floe is defined against that record. A floe's types must exist before
  the floe can evaluate, so they can never be declared inside `mkFloe`.
*/
{ lib }:

{ floeSet }:

let
  # A component floe is a directory and a lab floe is a file, so a set holds
  # both shapes. Only a directory can carry an `upstream.nix` beside it.
  dirOfFloe = path: if builtins.pathExists (path + "/default.nix") then path else dirOf path;

  floeDirs = lib.mapAttrs (_: dirOfFloe) floeSet;

  pinned = lib.filterAttrs (_: dir: builtins.pathExists (dir + "/upstream.nix")) floeDirs;

  # Whether a pin yields CRDs is a question about the *keys* of what
  # `upstream.nix` returns, and building an attrset forces no value — so this
  # answers it without the combinator library, which needs a `pkgs` that is
  # not available while the distribution record is still being built.
  #
  # The `throw` is the contract: anything here that actually reaches for a
  # fetcher says so loudly rather than evaluating to nonsense.
  yields =
    dir:
    import (dir + "/upstream.nix") {
      upstream = throw "lib/floe-crds.nix: a pin must declare its CRDs without fetching them";
    };

  withCrds = lib.filterAttrs (_: dir: yields dir ? crds) pinned;

  groupsIn =
    dir:
    let
      crdDir = dir + "/crds";
    in
    lib.optionals (builtins.pathExists crdDir) (
      map (f: {
        group = lib.removeSuffix ".nix" f;
        path = crdDir + "/${f}";
      }) (lib.attrNames (lib.filterAttrs (_: k: k == "regular") (builtins.readDir crdDir)))
    );
in
{
  # floe name -> the function yielding its CRD artifact, for `cata-build
  # generate`. Called with the combinator library.
  sources = lib.mapAttrs (
    _: dir: upstream:
    (import (dir + "/upstream.nix") { inherit upstream; }).crds
  ) withCrds;

  # API group -> the generated type file. Keyed by the group verbatim, which is
  # also the filename and also the `apiVersion` prefix a floe writes — one
  # string, no mapping between the three.
  #
  # A group defined in two floes would be two files claiming one key, which
  # `floe-crd-groups` refuses.
  types = lib.listToAttrs (
    lib.concatMap (dir: map (g: lib.nameValuePair g.group g.path) (groupsIn dir)) (
      lib.attrValues withCrds
    )
  );
}
