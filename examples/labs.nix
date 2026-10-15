/*
  The example corpus, discovered and instantiated.

      import ./examples/labs.nix {
        inherit lib;
        cata = catallaxy.legacyPackages.${system};
      }
      -> { labs = { "minimal.local" = …; … }; fixtures = { every-floe = …; … }; }

  `labs` is `<name>/lab.nix` instantiated once per `<name>/envs/<env>.nix`, keyed
  `<name>.<env>` — a definition and its environments, which is what a lab is.
  `fixtures` is each `tests/<name>.nix`, keyed `<name>`: a fixture has one
  environment, so the file is the whole instantiation and there is nothing to
  share.

  This is read twice, and that is the point. `examples/flake.nix` exposes it the
  way a consumer would, and the root flake's checks take it as their corpus.
  Discovering it twice would let the thing that runs and the thing that is
  checked drift apart.

  It asks `cata` for `mkLab`, `catallaxy` and `floes` and nothing else, so the
  corpus is held to the same published surface a lab outside this repo is.
*/
{
  lib,
  cata,
}:

let
  labFileArgs = {
    inherit lib;
    inherit (cata) catallaxy floes;
  };

  named =
    key: lab:
    lib.throwIf (lab.name != key) (
      "the lab discovered as '${key}' calls itself '${lab.name}'. The name is what every host "
      + "port and the subnet are allocated from, and what `cata` is invoked with, so the two "
      + "cannot differ."
    ) lab;

  isNixFile = name: kind: kind == "regular" && lib.hasSuffix ".nix" name;

  instantiate =
    key: args: file:
    named key (cata.mkLab (import file args));

  labDirs = lib.filterAttrs (
    name: kind: kind == "directory" && builtins.pathExists (./labs + "/${name}/lab.nix")
  ) (builtins.readDir ./labs);

  envsOf =
    labName: _:
    let
      def = import (./labs + "/${labName}/lab.nix") labFileArgs;
      envDir = ./labs + "/${labName}/envs";
    in
    lib.mapAttrs' (
      filename: _:
      let
        key = "${labName}.${lib.removeSuffix ".nix" filename}";
      in
      lib.nameValuePair key (instantiate key (labFileArgs // { lab = def; }) (envDir + "/${filename}"))
    ) (lib.filterAttrs isNixFile (builtins.readDir envDir));

  fixtureDir = ./labs/tests;
in
{
  labs = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList envsOf labDirs);

  fixtures = lib.mapAttrs' (
    filename: _:
    let
      key = lib.removeSuffix ".nix" filename;
    in
    lib.nameValuePair key (instantiate key labFileArgs (fixtureDir + "/${filename}"))
  ) (lib.filterAttrs isNixFile (builtins.readDir fixtureDir));
}
