# The docker on the operator's machine, as a container host.
#
# Every lab's default. Which engine runs it is the operator's to say, not the
# lab's: on macOS `cata` starts Colima's `catallaxy` profile unless
# `CATA_COLIMA_DISABLE` is set, and everywhere else uses the environment's own
# socket. A lab that needs a particular VM names `colima-host` instead.
{ floe, sigs, ... }:

floe.mkFloe {
  name = "local-docker";
  summary = "The docker on the operator's machine, whatever runs it there.";

  provides.host = sigs.CONTAINER_HOST;

  modules = [
    {
      config.floe.provides.host.engine.local = { };
    }
  ];
}
