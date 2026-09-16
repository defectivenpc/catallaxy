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
  # `pkgs`, `cataCharts` and `k8sSpecs` are definition-time arguments rather
  # than floe inputs: `instantiate` deep-forces inputs, so a derivation could
  # not travel that way. A floe reads them to default its own `chart`, which
  # is why a lab no longer threads one.
  applyFloes =
    set:
    lib.mapAttrs (
      _: path:
      let
        def = import path {
          inherit
            lib
            pkgs
            catallaxy
            cataCharts
            k8sSpecs
            ;
          inherit (catallaxy) floe sigs kinds;
        };
      in
      def // { __functor = _: def.instantiate; }
    ) set;

  floes = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: applyFloes) (import ../floes));

  # Presets are applied after the floe set, because their members are drawn
  # from it. Same definition-time arguments, plus `floes` itself.
  presets = lib.mapAttrs (
    _: path:
    let
      def = import path {
        inherit
          lib
          pkgs
          catallaxy
          cataCharts
          k8sSpecs
          floes
          ;
        inherit (catallaxy) floe sigs kinds;
      };
    in
    def // { __functor = _: def.instantiate; }
  ) (import ../floes/presets);

  # catalogue :: { FloeName -> [SignatureName] }
  #
  # What each floe provides, read off its declaration — the same read
  # `nix/floe-docs.nix` makes to generate its page. Derived, so adding a floe
  # adds it here and deleting one removes it; there is no second list.
  #
  # Lazy: `link` forces this only when a hole has no provider and it has an
  # error to write.
  catalogue = lib.mapAttrs (_: def: map (s: s.name) (lib.attrValues def.provides)) floes;

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
      presets
      catalogue
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

  # The presets this distribution ships, as definitions — what `floe-docs`
  # renders a page from.
  presetSet = presets;

  # mkFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # What a consumer calls on its own floe directory. The built-in set is
  # built by the same function, so a floe outside this repo is handed the
  # same arguments as one inside it.
  mkFloes = applyFloes;
}
