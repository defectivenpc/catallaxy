# The lab's own authoritative DNS: Knot, serving the zone to the host and to
# every container on the lab network.
#
# It does not provide `DNS_ZONE`. That stays `floes.lab-zone`, which a lab
# declares whether or not it runs a server — the zone is what routes hang off
# and the floes that need it need it either way. This is the thing that
# *answers* for the zone, which is a different job and a separate unit.
#
# What it answers for is collected, not computed. A record per hostname the
# lab is the edge for, gathered from each cluster that exports its exposure —
# and nothing for a cluster that does not, which is how a cluster that is its
# own edge says so.
#
# That it is a `collects` and not an input is the whole reason this floe can
# exist. The zone's contents depend on what the clusters serve; computing that
# from a cluster's elaborated output and handing it in as an input is
# `infinite recursion`, because a unit of a link cannot be computed from that
# link's output. A collection resolves *inside* the link and a body runs after
# resolution, so the dependency is ordinary. ADR 0004.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens;
in
floe.mkFloe {
  name = "lab-dns";
  summary = "Knot, answering for the lab's zone from the host and from inside the network.";

  # One per lab. `lab-zone` names one authoritative server and this is it, so
  # two of them is a lab whose zone has two answers — and `singleton` is also
  # what lets `lab-egress` resolve the resolver without a lab naming which.
  singleton = true;

  inputs = {

    image = lib.mkOption {
      type = lib.types.str;
      default = "cznic/knot:latest";
      description = "Knot DNS container image.";
    };

    configureHost = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Point this machine's resolver at the lab during `cata lab up`, so
        `*.<zone>` resolves in a browser and in anything run by hand.

        Off by default because it needs `sudo` and edits configuration outside
        the lab, which is a poor default for a command whose job is to be
        reversible. The steps that do it and undo it exist only when this is
        on.
      '';
    };

    tsigKeyname = lib.mkOption {
      type = lib.types.str;
      default = "externaldns-key";
      description = "TSIG key name for RFC2136 dynamic updates.";
    };

    tsigSecret = lib.mkOption {
      type = lib.types.str;
      default = "kp4bgnFAVCmajGIqOW7rj0MNwRNZHBqMvYaLTwzPHgI=";
      description = ''
        Base64 TSIG secret.

        A fixed default, and deliberately so: this authorises updates to a
        throwaway zone served on loopback, and generating one per lab would put
        a value in the store that every lab then has to be told. A lab that
        exposes its DNS beyond the host should set its own.
      '';
    };

    tsigSecretAlg = lib.mkOption {
      type = lib.types.str;
      default = "hmac-sha256";
      description = "TSIG algorithm.";
    };
  };

  # The docker network and the gateway address on it, resolved rather than
  # threaded. Both were inputs the lab handed in from its own options, which
  # was the merge surface meeting the floe surface — until there was a floe
  # that *is* the network, at which point four floes taking it as a string
  # while a fifth answers it is the asymmetry.
  requires.network = sigs.LAB_NETWORK;

  # The domain this serves, resolved rather than threaded. `lab-zone` answers
  # it for every cluster in the lab and answered it for nothing on the host,
  # so the lab read one option and wrote it into five instantiations with
  # nothing checking that they agreed.
  requires.zone = sigs.DNS_ZONE;

  # One contribution per cluster the lab fronts. A cluster that is its own edge
  # exports no exposure, so it is simply not in here — rather than in here with
  # a flag saying to skip it.
  collects.exposure = sigs.HOST_EXPOSURE;

  provides.service = sigs.HOST_SERVICE;
  provides.step = sigs.LAB_STEPS;

  # What else on the lab's network resolves through. One per lab or none, which
  # is what `singleton` says: two Knots authoritative for one zone is not a
  # state worth being able to write.
  provides.resolver = sigs.HOST_RESOLVER;

  # Where it answers, as `cata lab dns` points the host resolver at it. Its
  # own account of itself: the zone, the port and the key are all facts this
  # floe already holds, and a lab that runs no resolver emits none.
  out.dnsInfo = kinds.dnsInfo;

  body =
    {
      inputs,
      collects,
      requires,
      ...
    }:
    let
      network = requires.network;
      inherit (requires.zone) zone;

      containerName = catallaxy.hostContainerFor network.name "dns";

      inherit (requires.zone) port;
      relativeTo = host: lib.removeSuffix ".${zone}" host;

      hosts = lib.unique (lib.concatMap (e: e.hosts) (lib.attrValues collects.exposure));

      records = lib.concatMapStringsSep "\n    " (
        h: "${relativeTo h}   IN  A   ${network.gateway}"
      ) hosts;
    in
    {
      provides.resolver = {
        container = containerName;
      };

      out.dnsInfo = {
        host = "127.0.0.1";
        inherit (inputs) tsigKeyname tsigSecret tsigSecretAlg;
        inherit zone port;
      };

      provides.service = {
        description = "Knot DNS server (${zone})";
        container = containerName;
        inherit (inputs) image;

        command = [ "knotd" ];
        ports = [
          "${toString port}:53/tcp"
          "${toString port}:53/udp"
        ];

        networks = [ network.name ];
        dnsContainers = [ ];
        extraMounts = [ ];

        readyProbe = null;

        volumes = {
          "/config/knot.conf".content = ''
            server:
              listen: 0.0.0.0@53

            log:
              - target: stdout
                any: info

            key:
              - id: ${inputs.tsigKeyname}
                algorithm: ${inputs.tsigSecretAlg}
                secret: ${inputs.tsigSecret}

            acl:
              - id: update-acl
                key: ${inputs.tsigKeyname}
                action: [update, transfer]

            zone:
              - domain: ${zone}.
                storage: /storage
                file: ${zone}.zone
                acl: update-acl
          '';

          "/storage/${zone}.zone".content = ''
            $ORIGIN ${zone}.
            $TTL 300

            @   IN  SOA ns1.${zone}. admin.${zone}. (
                    2024010101  ; serial
                    3600        ; refresh
                    900         ; retry
                    604800      ; expire
                    300         ; minimum TTL
                )

            @   IN  NS  ns1.${zone}.
            ns1 IN  A   127.0.0.1
            ${records}
          '';
        };

      };

      provides.step.steps = lib.optionalAttrs inputs.configureHost {
        dns-setup = {
          kind = "dns-setup";
          description = "Point host DNS for '${zone}' at the lab resolver";
          provides = [ planTokens.lab.hostDns ];
          afterLab = "services";
          params = {
            host = "127.0.0.1";
            port = inputs.hostPort;
            inherit zone;
          };
        };

        dns-teardown = {
          kind = "dns-teardown";
          description = "Remove host DNS configuration for '${zone}'";
          provides = [ planTokens.lab.hostDnsRemoved ];
          params = {
            inherit zone;
          };
        };
      };
    };
}
