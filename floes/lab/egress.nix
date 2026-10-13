# A forward proxy inside the lab network, so a tool on the host can reach a
# lab hostname.
#
# The host half of a lab, as a floe. It installs nothing into any cluster and
# answers no signature: what it contributes is a container, which is the whole
# of what `catallaxy.hostService` is for.
#
# The first of these to move. It was a module under `modules/lab/host/`, which
# is where the rest still are — and the reason this one went first is that it
# is the only host service with no plan steps of its own and nothing in a
# cluster that reads it. ADR 0003's second half is the others.
#
# No `enable`. A floe absent from the lab's units is simply not there, which is
# what `lab.egress.enable` was standing in for.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

floe.mkFloe {
  name = "lab-egress";
  summary = "A forward proxy on the lab network, so host tools resolve lab hostnames.";

  inputs = {
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Loopback port the proxy is published on.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one: an allocated port looks free in a table of
        registered names and may not be — the ranges contain 5353 (mDNS) and
        5355 (LLMNR), and a host already running something is a fact no
        allocation can see.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/querateam/docker-tinyproxy:latest";
      description = "tinyproxy container image.";
    };
  };

  # The docker network and the gateway address on it, resolved rather than
  # threaded. Both were inputs the lab handed in from its own options, which
  # was the merge surface meeting the floe surface — until there was a floe
  # that *is* the network, at which point four floes taking it as a string
  # while a fifth answers it is the asymmetry.
  requires.network = sigs.LAB_NETWORK;

  # The zone, for the same reason and from the same place. It was a `zone`
  # string input in four host floes at once while `lab-zone` answered it for
  # every cluster — so the lab read one option and wrote it into five
  # instantiations, with nothing checking that they agreed.
  requires.zone = sigs.DNS_ZONE;

  # What this resolves through, so a request for a lab hostname gets the lab's
  # answer rather than the host's. Optional, and unwired is the honest answer:
  # a lab that runs no resolver of its own is a lab whose hostnames resolve
  # only for whatever already knows them.
  #
  # It was a `resolvers` list of container names the lab filled by reading
  # `lab.dns.enable` and `lab.dns.containerName` — one floe's configuration
  # read out of another's options.
  optional.resolver = sigs.HOST_RESOLVER;

  provides.service = sigs.HOST_SERVICE;

  body =
    { inputs, requires, ... }:
    let
      network = requires.network;

      containerName = catallaxy.hostContainerFor network.name "egress";
      port = if inputs.port != null then inputs.port else (catallaxy.allocationFor network.name).egress;
    in
    {
      provides.service = {
        description = "Forward proxy inside the lab network (${requires.zone.zone})";
        container = containerName;
        inherit (inputs) image;

        command = [ ];
        ports = [ "127.0.0.1:${toString port}:8888" ];
        networks = [ network.name ];
        dnsContainers = lib.optional (requires.resolver != null) requires.resolver.container;

        readyProbe = null;
        extraMounts = [ ];

        volumes."/etc/tinyproxy/tinyproxy.conf".content = ''
          Port 8888
          Listen 0.0.0.0
          Timeout 600
          Allow 0.0.0.0/0
          ConnectPort 443
          ConnectPort 80
          LogLevel Info
        '';
      };
    };
}
