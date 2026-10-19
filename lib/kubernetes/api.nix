{
  lib,
  floeCore,

  specFile,

  crdGroups,
}:

import ./schema-to-type.nix
  {
    inherit lib;
    T = floeCore.T;
  }
  {
    spec = builtins.fromJSON (builtins.readFile specFile);
    inherit crdGroups;
  }
