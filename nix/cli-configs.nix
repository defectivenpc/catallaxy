{
  lib,
  pkgs,
  labDefs,
}:

let
  omitted = [
    "deploymentPlan"
    "teardownPlan"
  ];

  canonical =
    name: lab:
    pkgs.runCommand "cli-config-${name}.json"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.gnused
        ];
        raw = builtins.toJSON (removeAttrs lab.cliConfig omitted);
        passAsFile = [ "raw" ];
      }
      ''
        jq -S . < "$rawPath" \
          | sed 's|/nix/store/[a-z0-9]\{32\}-|/nix/store/HASH-|g' > $out
      '';
in
pkgs.runCommand "cli-configs" { } ''
  mkdir -p $out
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: lab: "cp ${canonical name lab} $out/${name}.json") labDefs
  )}
''
