# A docker engine on another machine, reached over SSH, as a container host.
#
# Everything the lab publishes there binds the host's loopback, never its
# LAN; `cata` carries each port back to the same number on the operator
# machine through one SSH tunnel per lab, and copies the files a container
# mounts to the host before it starts. The operator needs key-based SSH to
# it and its user in the `docker` group; the host needs `rsync`.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "ssh-docker-host";
  summary = "A docker engine on another machine, reached over SSH and tunnelled back to this one.";

  inputs = {
    address = lib.mkOption {
      type = lib.types.str;
      example = "10.0.0.11";
      description = "Where the host is, as `ssh` dials it. Required.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Who to log in as. Null leaves it to the operator's SSH config, which
        is the place to say it once for every lab on that host.
      '';
    };
  };

  provides.host = sigs.CONTAINER_HOST;

  modules = [
    (
      { config, ... }:
      {
        config.floe.provides.host.engine.ssh = { inherit (config.floe.inputs) address user; };
      }
    )
  ];
}
