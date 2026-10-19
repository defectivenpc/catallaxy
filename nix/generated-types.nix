{
  lib,
  pkgs,
  cata,
  crdSources,
}:

let
  generate =
    name: config:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          cata
        ];
        json = builtins.toJSON ({ outputDir = "out"; } // config);
        passAsFile = [ "json" ];
      }
      ''
        mkdir -p $out
        cata-build generate "$jsonPath" --output $out
      '';

  floeTypes = lib.mapAttrs (
    floe: yaml: generate "generated-types-${floe}" { crds.${floe} = "${yaml}"; }
  ) crdSources;
in
{
  inherit floeTypes;

  all = pkgs.runCommand "generated-types" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (floe: drv: ''
        cp -r ${drv}/${floe} $out/${floe}
      '') floeTypes
    )
  );
}
