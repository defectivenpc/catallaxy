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
