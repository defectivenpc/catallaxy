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

  # The shipped set, with the framework arguments already applied, so a lab
  # writes `floes.cert-manager { }` rather than importing and applying each
  # one by hand. That boilerplate was four lines for four floes; `every-floe`
  # has ten and the full catalogue has twenty-nine.
  #
  # `pkgs` is a definition-time argument, not a floe input: a floe that has to
  # derive something at build time — pulling a CRD file out of its chart, say
  # — needs it, and `instantiate` deep-forces inputs, so a derivation could
  # not travel that way even if it wanted to.
  applyFloes =
    set:
    lib.mapAttrs (
      _: path:
      let
        def = import path {
          inherit lib pkgs;
          inherit (catallaxy) floe sigs kinds;
        };
      in
      # Callable directly: `floes.gateway { baseDomain = …; }` is
      # `.instantiate`, and the definition is still reachable for anything
      # that wants the header without an instance.
      def // { __functor = _: def.instantiate; }
    ) set;

  # Flattened across `cluster` and `provisioners`: the split is how the set is
  # organised on disk, not a namespace a lab has to spell. Names are unique
  # across both, and `floes/default.nix` is the one place that would notice if
  # they stopped being.
  floes = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: applyFloes) (import ../floes));

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

  /*
    A lab that is *supposed* to be refused, evaluated without throwing.

    `mkLab` throws on a failed assertion, which is right for a lab someone is
    building and useless for a check that a wrong one is caught: `tryEval`
    reports only that something failed, so a test written against it passes
    when the lab fails for an entirely unrelated reason. That happened in this
    repo — five refusal cases in `nix/checks/secret-sharing.nix` were all
    dying on a coherence check rather than the thing each meant to test, and
    only a paired positive control revealed it.

    Returns the list of violated messages, so a test can assert on *which*
    rule fired. Null means the lab did not evaluate at all, which is a
    different failure and must not read as a refusal.

    `force` names what to evaluate strictly. Assertions are collected lazily,
    so an option nothing reads never runs the code that would object.
  */
  labRefusal =
    {
      modules,
      force ? (config: config.lab.name),
    }:
    let
      result = lib.evalModules {
        modules = [ ../modules/lab ] ++ modules;
        specialArgs = labSpecialArgs;
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

  # The same, for a failure that is a `throw` rather than an assertion — the
  # elaborator's coherence checks are throws, because there is no config to
  # hang an assertion on by the time they run.
  labForce =
    { modules, force }:
    builtins.tryEval (
      builtins.deepSeq (force
        (lib.evalModules {
          modules = [ ../modules/lab ] ++ modules;
          specialArgs = labSpecialArgs;
        }).config
      ) "evaluated"
    );

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

  # Labs that exist to be checked rather than run: one file each, named by
  # its basename, no environments. They render and snapshot like any other
  # and never enter the e2e set, which is what makes them the cheap place to
  # pin behaviour no example happens to exercise.
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
    evalModule
    mkLab
    labRefusal
    labForce
    discoverLabs
    discoverFixtures
    ;
}
