# The plan step schema, written out.
#
# One page, and it is the one thing in the old option reference that was never
# the lab's. A floe declares `provides.step = sigs.LAB_STEPS` and writes these
# fields; `lib/eval/step-type.nix` is the type that accepts them, and
# `nixosOptionsDoc` over exactly that module is what makes the page unable to
# describe a field the merge would reject.
#
# The lab's own reference used to be here too, from `nixosOptionsDoc` over the
# tree `mkLab` evaluated. A lab is a floe now, so its inputs are a floe's and
# `nix/floe-docs.nix` renders them from the same declarations it renders every
# other module's from — one generator over one source, where there were two.
{
  lib,
  pkgs,
}:

let
  stepTypes = import ../lib/eval/step-type.nix { inherit lib; };

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
    inherit (lib.evalModules { modules = [ stepTypes.stepsModule ]; }) options;
    warningsAreErrors = false;
    transformOptions = opt: opt // { declarations = map relative opt.declarations; };
  };
in
doc.optionsJSON
