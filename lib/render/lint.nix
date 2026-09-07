# The lint channel -> executables under `$out/lint/<cluster>/`.
#
# `cata lab lint` walks that directory, takes each file name as the check
# name, and looks that name up in `metadata.json` to learn its severity,
# scope and output format (`cli/src/lint/mod.rs:271`). A check whose file name
# and metadata key disagree still runs, but silently as a per-file exit-code
# warning — so both sides sanitize through `bundle-key.nix` and nowhere else.
#
# Each script is run with `CLUSTER` and `MANIFEST_DIR` in the environment. A
# `per-file` check is additionally given the manifest path as `$1`.
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
