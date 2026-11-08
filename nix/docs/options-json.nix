{
  lib,
  pkgs,
}:

let
  stepTypes = (import ../../steps { inherit lib; }).types;

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
