# The lab's DNS zone, as a floe.
#
# The first floe that lives at lab scope rather than in a cluster. It installs
# nothing — there is no cluster for it to render into — and exists to answer
# `DNS_ZONE` for every cluster in the lab.
#
# Why that is worth a floe: the zone, the server's address and its port are
# facts the lab decides, and two floes in every cluster need all three.
# `lab-dns` teaches CoreDNS about the zone and `external-dns` publishes into
# it, and both took the same three values as inputs threaded by hand at each
# instantiation — six arguments a lab author had to keep consistent, with
# nothing checking that they were.
#
# The `lab.dns.*` options remain the authoring surface: an environment still
# sets `hostPort`, and the lab constructs this from the merged result. That
# split is the point. The module system is good at merging partial
# configuration from several files and bad at inter-component interfaces; the
# floe interface is the other way around. The lab keeps the first job and
# hands the second here.
{
  lib,
  floe,
  sigs,
  ...
}:

floe.mkFloe {
  name = "lab-zone";

  inputs = {
    zone = lib.mkOption {
      type = lib.types.str;
      description = "The lab's DNS zone, as `lab.test`. Required.";
    };

    server = lib.mkOption {
      type = lib.types.str;
      description = ''
        Where the authoritative server answers, from inside the lab network.
        Required.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5354;
      description = "Port that server answers on.";
    };
  };

  # Nothing. A floe at lab scope has no cluster to require and nothing to
  # install; what it has is an answer.
  provides.zone = sigs.DNS_ZONE;

  modules = [
    (
      { config, ... }:
      {
        config.floe.provides.zone = {
          inherit (config.floe.inputs) zone server port;
        };
      }
    )
  ];
}
