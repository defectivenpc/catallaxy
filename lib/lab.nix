# Evaluating a lab, and finding the ones in `examples/labs/`.
{
  lib,
  pkgs,
  cataCharts,
  k8sSpecs,
  examplesPath,
}:

let
  catallaxy = import ./floe-catallaxy { inherit lib pkgs; };
  floeSet = import ../floes;

  # `lib.evalModules` plus a strict read of one option path. An assertion that
  # is collected and never read is a comment; this makes a violated one fail
  # `nix eval`, which is before anything reaches a cluster.
  evalModule =
    {
      modules,
      specialArgs ? { },
    }:
    let
      result = lib.evalModules { inherit modules specialArgs; };
      failed = builtins.filter (a: !a.assertion) (result.config.assertions or [ ]);
    in
    if failed != [ ] then
      throw ("Failed assertions:\n" + lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed)
    else
      result;

  mkLab =
    { modules }:
    evalModule {
      modules = [ ../modules/lab ] ++ modules;
      specialArgs = {
        inherit
          lib
          pkgs
          catallaxy
          cataCharts
          k8sSpecs
          floeSet
          ;
      };
    };

  # `examples/labs/<dir>/lab.nix` crossed with `<dir>/envs/*.nix`, giving
  # `<dir>.<env>`. The lab file is first in the module list, so it uses
  # `mkDefault` for anything an environment overrides.
  discoverLabs =
    let
      isEnv = name: kind: kind == "regular" && lib.hasSuffix ".nix" name;

      labDirs = lib.filterAttrs (
        name: kind: kind == "directory" && builtins.pathExists (examplesPath + "/${name}/lab.nix")
      ) (builtins.readDir examplesPath);

      envsOf =
        labName: _:
        let
          envDir = examplesPath + "/${labName}/envs";
        in
        lib.mapAttrs' (
          filename: _:
          lib.nameValuePair "${labName}.${lib.removeSuffix ".nix" filename}" (mkLab {
            modules = [
              (examplesPath + "/${labName}/lab.nix")
              (envDir + "/${filename}")
            ];
          })
        ) (lib.filterAttrs isEnv (builtins.readDir envDir));
    in
    lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList envsOf labDirs);
in
{
  inherit evalModule mkLab discoverLabs;
}
