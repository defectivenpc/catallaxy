# A particular Colima VM on the operator's machine, as a container host.
#
# For a lab that wants its own profile; `local-docker` already means Colima's
# `catallaxy` profile on macOS. The lab names the profile; how big the VM is stays the
# operator's (`CATA_COLIMA_{CPU,MEMORY,DISK}`), because one profile serves
# every lab they run and two labs asking for different sizes would race to
# start it. `cata` starts the VM if it is not up, and `CATA_COLIMA_DISABLE`
# points the lab at the local daemon instead, for an operator on Docker
# Desktop.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "colima-host";
  summary = "A Colima VM on the operator's machine, started by `cata` when it is not running.";

  inputs.profile = lib.mkOption {
    type = lib.types.str;
    default = "catallaxy";
    description = ''
      The Colima profile to run on.

      Shared by every lab that names it, so the default is one VM per
      operator rather than one per lab.
    '';
  };

  provides.host = sigs.CONTAINER_HOST;

  modules = [
    (
      { config, ... }:
      {
        config.floe.provides.host.engine.colima = { inherit (config.floe.inputs) profile; };
      }
    )
  ];
}
