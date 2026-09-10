# The lab option tree, written out.
#
# `cata-build docs render` has existed and been reachable the whole time; what
# was missing was the JSON to feed it. This is that: `nixosOptionsDoc` over the
# same module tree `mkLab` evaluates, so the reference cannot describe options
# a lab does not have.
#
# Floes are not in here. Since RFC 0001 a floe's inputs are function arguments
# rather than options, so `lab.clusters.<c>.floes.<n>` is one opaque option and
# there is nothing under it to route. Floe interfaces come from
# `nix/floe-docs.nix`, which reads the definitions and can also say what a floe
# emits. Two generators, two sources, no overlap.
{
  lib,
  pkgs,
  mkLab,
}:

let
  # A lab with no clusters: the option tree is what is declared, not what any
  # particular lab sets, and `<name>` placeholders come from the module system
  # rather than from an instance.
  evaluated = mkLab { modules = [ { lab.name = "options-reference"; } ]; };

  # `declarations` are absolute store paths, so they carry the hash of the
  # source and move on every commit. Repo-relative is both stable and what a
  # reader can actually open.
  relative =
    path:
    let
      matched = builtins.match "/nix/store/[^/]*-source/(.*)" (toString path);
    in
    if matched == null then toString path else builtins.head matched;

  doc = pkgs.nixosOptionsDoc {
    inherit (evaluated) options;
    warningsAreErrors = false;
    transformOptions = opt: opt // { declarations = map relative opt.declarations; };
  };
in
doc.optionsJSON
