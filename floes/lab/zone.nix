# The lab's DNS zone, as a floe.
#
# The first floe that lives at lab scope rather than in a cluster. It installs
# nothing — there is no cluster for it to render into — and exists to answer
# `DNS_ZONE` for every cluster in the lab.
#
# Why that is worth a floe: the zone, the server's address and its port are
# facts the lab decides, and two floes in every cluster need all three.
# `coredns-zone` teaches CoreDNS about the zone and `external-dns` publishes into
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
  catallaxy,
  ...
}:

floe.mkFloe {
  name = "lab-zone";
  summary = "The lab's DNS zone, offered downward so every cluster resolves against one.";

  inputs = {
    zone = lib.mkOption {
      type = lib.types.str;
      description = "The lab's DNS zone, as `lab.test`. Required.";
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Port the zone's server answers on: what `lab-dns` publishes and what a
        pod forwards to.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one — the allocation spans 5300-5555, which
        contains 5353 (mDNS) and 5355 (LLMNR, held by systemd-resolved on most
        Linux hosts), so two names in 256 land on a port that looks free and
        is not.

        One number in one place. `lab-dns` publishes on what this says rather
        than taking a port of its own; it was two options, `lab.dns.port`
        defaulting to `lab.dns.hostPort`, with the lab handing each to a
        different floe.
      '';
    };
  };

  # Where the server answers from, which is the lab's gateway address. It was
  # a `server` input the lab handed in from `lab.network.gateway`; the floe
  # that *is* the network answers it now, so the address is stated once.
  #
  # Still unconditional, and that is why `lab-network` is placed whether or
  # not it creates anything: a lab that runs no DNS server still declares the
  # zone its routes hang off, and this floe exists to make that sayable.
  requires.network = sigs.LAB_NETWORK;

  provides.zone = sigs.DNS_ZONE;

  modules = [
    (
      { config, ... }:
      {
        config.floe.provides.zone = {
          inherit (config.floe.inputs) zone;
          server = config.floe.requires.network.gateway;

          port =
            if config.floe.inputs.port != null then
              config.floe.inputs.port
            else
              (catallaxy.allocationFor config.floe.requires.network.name).dns;
        };
      }
    )
  ];
}
