{
  lib,
  pkgs,
  pureLib,
  cataCharts,
  k8sSpecs,
  modulesPath,
  examplesPath,
  defaultFloeSet,

  tools ? [ ],
  cataWrapped ? null,
}:

let

  labModules =
    floes: modules:
    [
      modulesPath
      {
        _module.args.cataCharts = cataCharts;
        _module.args.k8sSpecs = k8sSpecs;
        _module.args.k8sHelpers = import ./k8s-helpers.nix { inherit lib; };
        _module.args.contracts = import ./contracts { inherit lib; };
      }
    ]
    # Lab-scope floes are ordinary top-level modules, so they go in the list.
    # Cluster-scope ones cannot: they belong inside the cluster submodule, and
    # `imports` is resolved before the fixpoint that `_module.args` lives in.
    # Those travel by `specialArgs` instead — see `clusterFloes` below.
    ++ lib.attrValues floes.lab
    ++ modules;

  labSpecialArgs = floes: {
    inherit lib pkgs;
    clusterFloes = lib.attrValues floes.cluster;
  };

  mkLab =
    {
      modules,
      floes ? defaultFloeSet,
    }:
    pureLib.evalModule {
      modules = labModules floes modules;
      specialArgs = labSpecialArgs floes;
    };

  labRefusal =
    {
      modules,
      floes ? defaultFloeSet,
      force ? (config: config.lab.name),
    }:
    let
      result = lib.evalModules {
        modules = labModules floes modules;
        specialArgs = labSpecialArgs floes;
      };

      messages = map (a: a.message) (lib.filter (a: !a.assertion) result.config.assertions);

      attempt = builtins.tryEval (
        builtins.deepSeq [
          messages
          (force result.config)
        ] messages
      );
    in
    if attempt.success then attempt.value else null;

  labForce =
    {
      modules,
      force,
      floes ? defaultFloeSet,
    }:
    builtins.tryEval (
      builtins.deepSeq (force
        (lib.evalModules {
          modules = labModules floes modules;
          specialArgs = labSpecialArgs floes;
        }).config
      ) "evaluated"
    );

  discoverExampleLabs =
    let
      isNixFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;

      labDirs = lib.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (examplesPath + "/${name}/labs/default.nix")
      ) (builtins.readDir examplesPath);

      labsIn =
        labName: _:
        let
          envDir = examplesPath + "/${labName}/envs";
          envFiles = lib.filterAttrs isNixFile (builtins.readDir envDir);
        in
        lib.mapAttrs' (
          filename: _:
          lib.nameValuePair "${labName}.${lib.removeSuffix ".nix" filename}" (mkLab {
            modules = [
              (examplesPath + "/${labName}/labs/default.nix")
              (envDir + "/${filename}")
            ];
          })
        ) envFiles;
    in
    lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList labsIn labDirs);

  # Labs that exist to be checked rather than run. They render and snapshot
  # like any other, and never enter the e2e set, which is what makes them the
  # cheap place to pin behaviour no example happens to exercise.
  discoverFixtureLabs =
    let
      dir = examplesPath + "/tests";
      isLab = name: type: type == "regular" && lib.hasSuffix ".nix" name;
    in
    lib.mapAttrs' (
      filename: _:
      lib.nameValuePair (lib.removeSuffix ".nix" filename) (mkLab {
        modules = [ (dir + "/${filename}") ];
      })
    ) (lib.filterAttrs isLab (builtins.readDir dir));

  mkLabShell =
    lab:
    let
      out = lab.config.lab.out;
      name = lab.config.lab.name;
    in
    pkgs.mkShell (
      out.shell.variables
      // {
        packages = tools ++ out.shell.packages ++ lib.optional (cataWrapped != null) cataWrapped;
        shellHook = ''
          if trust_env="$(cata lab env ${lib.escapeShellArg name} 2>/dev/null)"; then
            eval "$trust_env"
            echo "catallaxy: lab '${name}' CA trusted in this shell"
          else
            echo "catallaxy: lab '${name}' has no CA yet; run 'cata lab up' for trusted *.${
              lab.config.lab.dns.zone or "<zone>"
            }"
          fi
        '';
      }
    );

  k8sTypegenConfig = {
    outputDir = "modules/lab/cluster/lib/kubernetes/generated";
    k8sVersions = lib.mapAttrs (_: spec: "${spec}") k8sSpecs.specs;
    crds = k8sSpecs.crds;
  };

in
{
  inherit
    mkLab
    labRefusal
    labForce
    mkLabShell
    discoverExampleLabs
    discoverFixtureLabs
    k8sTypegenConfig
    ;
}
