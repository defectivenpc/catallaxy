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

  # applyFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # `pkgs` is a definition-time argument, not a floe input: `instantiate`
  # deep-forces inputs, so a derivation could not travel that way.
  applyFloes =
    set:
    lib.mapAttrs (
      _: path:
      let
        def = import path {
          inherit lib pkgs catallaxy;
          inherit (catallaxy) floe sigs kinds;
        };
      in
      def // { __functor = _: def.instantiate; }
    ) set;

  floes = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: applyFloes) (import ../floes));

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

  labSpecialArgs = {
    inherit
      lib
      pkgs
      catallaxy
      cataCharts
      k8sSpecs
      floes
      ;
  };

  mkLab =
    { modules }:
    evalModule {
      modules = [ ../modules/lab ] ++ modules;
      specialArgs = labSpecialArgs;
    };

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

  discoverFixtures =
    let
      dir = examplesPath + "/tests";
      isLab = name: kind: kind == "regular" && lib.hasSuffix ".nix" name;
    in
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.mapAttrs' (
        filename: _:
        lib.nameValuePair (lib.removeSuffix ".nix" filename) (mkLab {
          modules = [ (dir + "/${filename}") ];
        })
      ) (lib.filterAttrs isLab (builtins.readDir dir))
    );
in
{
  inherit
    mkLab
    discoverLabs
    discoverFixtures
    ;

  # mkFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # What a consumer calls on its own floe directory. The built-in set is
  # built by the same function, so a floe outside this repo is handed the
  # same arguments as one inside it.
  mkFloes = applyFloes;
}
