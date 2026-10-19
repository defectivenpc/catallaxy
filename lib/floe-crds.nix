{ lib }:

{ floeSet }:

let
  dirOfFloe = path: if builtins.pathExists (path + "/default.nix") then path else dirOf path;

  floeDirs = lib.mapAttrs (_: dirOfFloe) floeSet;

  pinned = lib.filterAttrs (_: dir: builtins.pathExists (dir + "/upstream.nix")) floeDirs;

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
      map
        (f: {
          group = lib.removeSuffix ".json" f;
          path = crdDir + "/${f}";
        })
        (
          lib.attrNames (
            lib.filterAttrs (f: k: k == "regular" && lib.hasSuffix ".json" f) (builtins.readDir crdDir)
          )
        )
    );
in
{
  sources = lib.mapAttrs (
    _: dir: upstream:
    (import (dir + "/upstream.nix") { inherit upstream; }).crds
  ) withCrds;

  groups = lib.listToAttrs (
    lib.concatMap (
      dir:
      map (g: lib.nameValuePair g.group (builtins.fromJSON (builtins.readFile g.path))) (groupsIn dir)
    ) (lib.attrValues withCrds)
  );
}
