# Rule 1: a floe reads another floe's `exports`, never its internals.
#
# A regex over source text, because Nix offers no parser to ask instead, which
# is why `sourceDir` is a directory rather than the floe set: the module values
# a set carries have no source to read. A floe set handed over as a flake
# output has no directory, and gets no boundary check — see the canary below
# for why that is safer than silently checking nothing.
{
  lib,
  sourceDir,
}:

let
  floesDir = sourceDir;

  inherit (builtins)
    readDir
    readFile
    attrNames
    split
    isList
    ;
  inherit (lib) filterAttrs concatMap filter;

  floeNames = attrNames (filterAttrs (_: t: t == "directory") (readDir floesDir));

  nixFilesIn =
    floe:
    let
      dir = floesDir + "/${floe}";
      entries = filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (readDir dir);
    in
    map (n: {
      inherit floe;
      name = n;
      path = dir + "/${n}";
    }) (attrNames entries);

  matchesIn = content: filter isList (split "config\\.floes\\.([a-zA-Z-]+)\\.([a-zA-Z_]+)" content);

  violationsFor =
    file:
    let
      hits = matchesIn (readFile file.path);
      bad = filter (m: (builtins.elemAt m 0) != file.floe && (builtins.elemAt m 1) != "exports") hits;
    in
    map (
      m:
      "${file.floe}/${file.name} reads `config.floes.${builtins.elemAt m 0}.${builtins.elemAt m 1}`: "
      + "that is ${builtins.elemAt m 0}'s internal state, not its interface. "
      + "Read `peers.${builtins.elemAt m 0}.<field>` instead, and if the field you need is not "
      + "exported, add it to ${builtins.elemAt m 0}'s `exports`; publishing is that floe's call."
    ) bad;

  # The extractor above is a regex over source text, because Nix offers no
  # parser to ask instead. That has one failure mode worth guarding: when it
  # stops matching it returns nothing, and no violations is indistinguishable
  # from a clean tree. So run it against a fixture that plants exactly one
  # violation beside two legitimate reads, and fail if the count is not one —
  # which catches both a pattern that has gone blind and one that has started
  # flagging everything.
  canaryFile = {
    floe = "canary";
    name = "floe-boundary-violation.nix";
    path = ./fixtures/floe-boundary-violation.nix;
  };

  canaryFound = builtins.length (violationsFor canaryFile);

  canaryFailure = lib.optional (canaryFound != 1) ''
    the floe-boundary extractor found ${toString canaryFound} violation(s) in
    its own fixture, not 1.

    ${canaryFile.name} plants one read of another floe's internals beside a
    read of that floe's `exports` and a read of its own config. Finding none
    means the pattern no longer matches the source it is aimed at, and a
    check that matches nothing reports every floe as clean. Finding more than
    one means it is now flagging reads that are allowed.

    Fix `matchesIn` in lib/floe-checks/boundary.nix.
  '';

  violations = canaryFailure ++ concatMap violationsFor (concatMap nixFilesIn floeNames);
in
violations
