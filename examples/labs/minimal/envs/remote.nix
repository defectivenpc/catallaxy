# The minimal lab on a remote docker engine, reached over SSH.
#
# Nothing about the cluster differs from `minimal.local`; the host does. Point
# `address` and `user` at a machine you can `ssh` into with a key and whose
# user is in the `docker` group, then `cata lab up minimal.remote`.
{
  lab,
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ../clusters.nix { inherit catallaxy floes lib; };
in
lab {
  name = "minimal.remote";

  cluster = clusters.app { };

  provisioner = floes.k3d-cluster { };

  units.host = floes.ssh-docker-host {
    address = "10.10.100.177";
    user = "whitehead";
  };
}
