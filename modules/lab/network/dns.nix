# The lab's own authoritative DNS.
#
# Knot, serving `<zone>` to the host and to every container on the lab
# network. One wildcard answers for the whole zone, pointed at the docker
# bridge gateway, because every host-facing endpoint arrives through the
# ingress and the ingress routes by Host header.
#
# The TSIG key is here rather than invented per-lab because `external-dns`
# updates this zone over RFC2136 and needs a key it was told about. Nothing
# reads it yet; the key exists so the floe that will can be added without
# reshaping the service.
{
  config,
  lib,
  floes,
  ...
}:

let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  cfg = config.lab.dns;

  # Public hostnames the lab is the edge for, and whether it is the edge for
  # every cluster. Same filter as `modules/lab/host/proxy.nix`: a cluster with
  # `edge.mode != "proxy"` is reached at its own address, so pointing its
  # hostname at the lab bridge sends traffic to a proxy with no backend for it.
  proxiedHosts = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: c:
        lib.optionals (c.edge.mode == "proxy") (
          map (h: h.host) (lib.filter (h: h.tier == "public") c.out.exposedHosts)
        )
      ) config.lab.clusters
    )
  );

  labIsEveryEdge = lib.all (c: c.edge.mode == "proxy") (lib.attrValues config.lab.clusters);

  # `foo.zone.test.` -> `foo`, because the zone file has an $ORIGIN.
  relativeTo = host: lib.removeSuffix ".${cfg.zone}" host;

  knotConf = ''
    server:
      listen: 0.0.0.0@53

    log:
      - target: stdout
        any: info

    key:
      - id: ${cfg.tsigKeyname}
        algorithm: ${cfg.tsigSecretAlg}
        secret: ${cfg.tsigSecret}

    acl:
      - id: update-acl
        key: ${cfg.tsigKeyname}
        action: [update, transfer]

    zone:
      - domain: ${cfg.zone}.
        storage: /storage
        file: ${cfg.zone}.zone
        acl: update-acl
  '';

  zoneFile = ''
    $ORIGIN ${cfg.zone}.
    $TTL 300

    @   IN  SOA ns1.${cfg.zone}. admin.${cfg.zone}. (
            2024010101  ; serial
            3600        ; refresh
            900         ; retry
            604800      ; expire
            300         ; minimum TTL
        )

    @   IN  NS  ns1.${cfg.zone}.
    ns1 IN  A   127.0.0.1
    ${
      lib.optionalString (config.lab.proxy.enable && labIsEveryEdge) ''

        ; Every host-facing endpoint arrives through the ingress, which routes
        ; by Host header, so one wildcard answers for all of them. The target is
        ; the docker bridge gateway because the same zone is served to the host
        ; and to pods, and that address reaches the ingress's published port
        ; from both.
        ;
        ; A more specific record always wins, so a DNS controller keeps control
        ; of anything it publishes. Without this a lab that runs no such
        ; controller resolves nothing at all.
        *   IN  A   ${cfg.server}''
    }${
      lib.optionalString (config.lab.proxy.enable && !labIsEveryEdge) ''

        ; No wildcard: some cluster here is its own edge, and a wildcard would
        ; answer for its hostnames too — sending them to a proxy that has no
        ; backend for them (RFC 0005 §6.4). One record per hostname the lab
        ; really is the edge for, and nothing for the rest.
        ${lib.concatMapStringsSep "\n      " (h: "${relativeTo h}   IN  A   ${cfg.server}") proxiedHosts}''
    }
  '';
in
{
  options.lab.dns = {
    enable = mkEnableOption "an authoritative DNS server for the lab's zone";

    zone = mkOption {
      type = types.str;
      default = "${config.lab.name}.test";
      defaultText = lib.literalExpression ''"''${config.lab.name}.test"'';
      description = ''
        Domain the lab's hostnames hang off, handed to floes as their
        `baseDomain`.

        Meaningful even with `enable = false`: it is what routes are declared
        under and what `registry-setup` names the in-cluster registry at. What
        `enable` adds is something that answers for it.
      '';
    };

    configureHost = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Point this machine's resolver at the lab's DNS during `cata lab up`,
        so `*.<zone>` resolves in a browser and in anything run by hand.

        Off by default because it needs `sudo` and edits configuration outside
        the lab, which is a poor default for a command whose job is to be
        reversible. Left off, `cata lab verify` still probes every exposed
        host by resolving through the lab's own DNS, and
        `curl --resolve <host>:80:127.0.0.1` does the same by hand.

        `cata lab destroy` removes what it wrote.
      '';
    };

    server = mkOption {
      type = types.str;
      default = config.lab.network.gateway;
      defaultText = lib.literalExpression "config.lab.network.gateway";
      description = ''
        Where the DNS server answers from, as seen from inside the lab
        network. The bridge gateway, because that address is reachable both
        from pods and from the host.
      '';
    };

    port = mkOption {
      type = types.port;
      default = cfg.hostPort;
      defaultText = lib.literalExpression "config.lab.dns.hostPort";
      description = "Port clusters reach the DNS server on.";
    };

    hostPort = mkOption {
      type = types.port;
      default = 5354;
      description = ''
        Host-mapped port for the DNS server.

        5354 avoids 5353, which is mDNS. A lab moving off the default so it
        can run beside another should also skip 5355: that is LLMNR, which
        systemd-resolved holds on most Linux hosts, so it looks free in a
        table of registered names and is not.
      '';
    };

    tsigKeyname = mkOption {
      type = types.str;
      default = "externaldns-key";
      description = "TSIG key name for RFC2136 dynamic updates.";
    };

    tsigSecret = mkOption {
      type = types.str;
      default = "kp4bgnFAVCmajGIqOW7rj0MNwRNZHBqMvYaLTwzPHgI=";
      description = ''
        Base64 TSIG secret.

        A fixed default, and deliberately so: this authorises updates to a
        throwaway zone served on loopback, and generating one per lab would
        put a value in the store that every lab then has to be told. A lab
        that exposes its DNS beyond the host should set its own.
      '';
    };

    tsigSecretAlg = mkOption {
      type = types.str;
      default = "hmac-sha256";
      description = "TSIG algorithm.";
    };

    image = mkOption {
      type = types.str;
      default = "cznic/knot:latest";
      description = "Knot DNS container image.";
    };

    containerName = mkOption {
      type = types.str;
      default = "catallaxy-${config.lab.name}-dns";
      defaultText = lib.literalExpression ''"catallaxy-''${config.lab.name}-dns"'';
      description = "Docker container name for the DNS server.";
    };

    out = {
      service = mkOption {
        type = types.attrs;
        readOnly = true;
        description = "The `HostService` record `setup-services` starts.";
      };

      dnsInfo = mkOption {
        type = types.nullOr types.attrs;
        readOnly = true;
        description = ''
          What `cata lab dns` needs to point the host resolver here. Null when
          the lab runs no DNS, which is how the CLI knows to say so rather
          than to configure a resolver pointing at nothing.
        '';
      };
    };
  };

  # Unconditional, like `zone` itself: a lab that runs no DNS server of its
  # own still declares the zone its routes hang off, and the floes that need
  # to know it need to know it either way. `enable` adds something that
  # answers for the zone, not the zone.
  #
  # This is the merge surface meeting the floe surface. `lab.dns.*` stays what
  # an env file writes — `homelab/envs/dns.nix` sets `hostPort` and `port`
  # follows — and the lab builds one floe out of the merged result, so the
  # clusters read a resolved answer rather than each being handed three
  # arguments that can disagree.
  config.lab.provides.zone = floes.lab-zone { inherit (cfg) zone server port; };

  # `dnsInfo` is defined unconditionally and `service` under `mkIf`, which is
  # not an inconsistency: a read-only option counts its default as a
  # definition, so one carrying a null case has to express that case in its
  # value rather than in a default.
  config.lab.dns.out = {
    dnsInfo =
      if !cfg.enable then
        null
      else
        {
          host = "127.0.0.1";
          inherit (cfg)
            zone
            tsigKeyname
            tsigSecret
            tsigSecretAlg
            ;
          port = cfg.hostPort;
        };

    service = mkIf cfg.enable {
      description = "Knot DNS server (${cfg.zone})";
      container = cfg.containerName;
      inherit (cfg) image;
      command = [ "knotd" ];
      ports = [
        "${toString cfg.hostPort}:53/tcp"
        "${toString cfg.hostPort}:53/udp"
      ];
      volumes = {
        "/config/knot.conf".content = knotConf;
        "/storage/${cfg.zone}.zone".content = zoneFile;
      };

      # On the lab network, so `registry-setup` can read its address and write
      # a `lab-resolv.conf` the nodes can actually reach.
      networks = [ config.lab.name ];
    };
  };
}
