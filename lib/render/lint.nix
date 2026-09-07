# The lint channel -> executables under `$out/lint/<cluster>/`.
{ lib, pkgs }:

let
  inherit (import ../eval/bundle-key.nix { }) sanitize;
in
{
  inherit sanitize;

  # mkLintChecks :: { clusterName; checks } -> package or null
  #
  # `checks` is `cluster.out.lint`, keyed `<unit>/<bundle>/<name>`.
  mkLintChecks =
    { clusterName, checks }:
    let
      scripts = lib.mapAttrsToList (
        key: check:
        let
          name = sanitize key;
        in
        ''
          cp ${
            pkgs.writeShellApplication {
              inherit name;
              text = check.command;
            }
          }/bin/${name} $out/${clusterName}/${name}
        ''
      ) checks;
    in
    if checks == { } then
      null
    else
      pkgs.runCommand "lint-${clusterName}" { } ''
        mkdir -p $out/${clusterName}
        ${lib.concatStrings scripts}
      '';
}
