# Core functionality, written once against the interface.
#
# This file is the point of the spike. Everything in `./interface.nix` is
# declaration; this is the behaviour an author gets for free by instantiating
# it. Nothing here names a floe, and nothing a floe author writes has to name
# anything here.
#
# The model is `lib/services/lib.nix`, which is the whole of upstream's
# equivalent: `flattenMapServicesConfigToList` plus the two collectors built on
# it. That file is 40 lines and it is what makes a modular service worth
# being one — a service writes `assertions = [ … ]` and the containing system
# reports it, at any depth, with the option path attached.
#
# Split differently from upstream's, though. Theirs fuses the walk and the map
# into one recursive function per collector; this one walks once into a flat
# list of `{ loc; floe; }` and builds every collector on top. Same result, and
# it means adding a channel is a one-liner rather than another recursion.
{ lib }:

let
  inherit (lib)
    concatLists
    concatMap
    mapAttrsToList
    showOption
    getAttrFromPath
    hasAttrByPath
    mkMerge
    ;
in
rec {
  /**
    Every floe in the tree, depth-first, with the option path it sits at.

    `loc` is a real option path (`[ "floes" "k3d-local" "floes" "gateway" ]`),
    so `showOption` renders it the way an error message should read and
    nothing has to reconstruct the route by hand.
  */
  walk =
    prefix: floes:
    concatLists (
      mapAttrsToList (
        floeName: floe:
        let
          loc = prefix ++ [
            "floes"
            floeName
          ];
        in
        [
          {
            inherit loc floe;
            name = floeName;
          }
        ]
        ++ walk loc (floe.floes or { })
      ) floes
    );

  /**
    The tree as a flat list, rooted at a containing config's `floes`.
  */
  allFloes = config: walk [ ] (config.floes or { });

  /**
    Assertions from every floe at every depth, each message prefixed with the
    floe that made it.

    This is the thing eleven floes writing cluster-scope `assertions` cannot
    do today: the assertion lands in one flat list at the cluster, and the
    failure names no floe. Here the path comes from where the floe *is*, so it
    is right by construction rather than by the author remembering to say so.
  */
  collectAssertions =
    config:
    concatMap (
      entry:
      map (a: {
        inherit (a) assertion;
        message = "in ${showOption entry.loc}: ${a.message}";
      }) entry.floe.assertions or [ ]
    ) (allFloes config);

  /**
    As `collectAssertions`, for the non-fatal channel.
  */
  collectWarnings =
    config:
    concatMap (entry: map (w: "in ${showOption entry.loc}: ${w}") entry.floe.warnings or [ ]) (
      allFloes config
    );

  /**
    One contribution channel, merged across the whole tree.

    `path` is the channel's path on a floe (`[ "bundles" ]`,
    `[ "infra" "resources" ]`). Floes that do not have the channel — a lab floe
    asked for `bundles`, say — contribute nothing rather than failing, because
    which channels exist is decided by which extension is loaded and a
    collector should not have to know.

    `mkMerge` rather than `//`: two floes contributing different keys to the
    same channel must merge, and two contributing the *same* key must be a
    conflicting-definition error rather than a silent last-wins. That is the
    behaviour `modules/lab/cluster/bundles.nix:44` already has, and this is the
    same line written once for every channel instead of once per channel.
  */
  collectChannel =
    path: config:
    mkMerge (
      map (entry: getAttrFromPath path entry.floe) (
        builtins.filter (entry: hasAttrByPath path entry.floe) (allFloes config)
      )
    );

  /**
    Several channels at once, as an attrset ready to merge into a containing
    config.

    `channels` maps a target option path to the floe-side path it comes from,
    so a scope declares its fold as data:

        foldChannels config {
          bundles                = [ "bundles" ];
          steps                  = [ "steps" ];
          "cluster.prerequisites" = [ "prerequisites" ];
        }

    The eight hand-written `mkMerge (mapAttrsToList …)` folds in the cluster
    module become this table.
  */
  foldChannels =
    config: channels: lib.mapAttrs (_target: sourcePath: collectChannel sourcePath config) channels;
}
