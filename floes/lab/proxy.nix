# The lab's ingress: HAProxy in front of every cluster's gateway.
#
# This is what makes a hostname mean something. The resolver answers for the
# name with the bridge gateway's address, this listens there, and it routes by
# Host header to whichever cluster claimed the name.
#
# What it routes is collected, not computed. Each cluster the lab fronts
# exports its `HOST_EXPOSURE`, which carries the hostnames its workloads
# claimed *and* the address its provisioner answered — one record, because a
# route needs both and nothing else can pair them. A cluster that is its own
# edge exports none and is simply not in here.
#
# Terminate-only. The parked proxy also did SNI passthrough for an internal
# tier reached over a mesh; the current gateway floe has neither, and a mode
# with no way to select it is a branch nothing tests.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

floe.mkFloe {
  name = "lab-proxy";
  summary = "HAProxy, routing the lab's hostnames to the cluster that claimed them.";

  inputs = {
    httpPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Loopback port the HTTP listener is published on.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one: an allocated port looks free in a table of
        registered names and may not be — the ranges contain 5353 (mDNS) and
        5355 (LLMNR), and a host already running something is a fact no
        allocation can see.
      '';
    };

    httpsPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Loopback port the HTTPS listener is published on.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one: an allocated port looks free in a table of
        registered names and may not be — the ranges contain 5353 (mDNS) and
        5355 (LLMNR), and a host already running something is a fact no
        allocation can see.
      '';
    };

    idleTimeout = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = ''
        How long an idle connection is held open.

        Long, deliberately. HAProxy's defaults are tens of seconds, which
        orderly-closes the long-lived streams that gRPC and watch-based
        clients keep open — and the symptom is not a failure but a client
        that silently reconnects forever.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "haproxy:3.1-alpine";
      description = "HAProxy container image.";
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

  # Whether this lab terminates TLS, said by whether it has a root to
  # terminate with. It was a `tlsEnable` input the lab filled from
  # `lab.proxy.tls.enable` — an option defaulting to true that no lab ever set
  # — while the step that mints the certificate was gated on the same option
  # somewhere else. One statement now: a `lab-ca` in the link.
  optional.labCa = sigs.LAB_CA;

  # One contribution per cluster the lab fronts, keyed by the cluster, which
  # is also what names its backend.
  collects.exposure = sigs.HOST_EXPOSURE;

  provides.service = sigs.HOST_SERVICE;

  # What it routes, said by the thing that routes it. `cata lab verify` probes
  # these, and they are the same `routed` the `use_backend` lines come from, so
  # a hostname cannot be probed through a backend that was never written.
  out.routedHosts = kinds.routedHosts;

  body =
    {
      inputs,
      collects,
      requires,
      ...
    }:
    let
      network = requires.network;
      containerName = catallaxy.hostContainerFor network.name "ingress";

      allocation = catallaxy.allocationFor network.name;
      httpPort = if inputs.httpPort != null then inputs.httpPort else allocation.proxyHttp;
      httpsPort = if inputs.httpsPort != null then inputs.httpsPort else allocation.proxyHttps;
      labCa = requires.labCa;
      tls = labCa != null;
      fronted = lib.filterAttrs (_: e: e.hosts != [ ]) collects.exposure;

      backendless = lib.attrNames (lib.filterAttrs (_: e: e.edge == null) fronted);

      routed = lib.filterAttrs (_: e: e.edge != null) fronted;

      haproxyConfig =
        let
          routes = lib.concatStringsSep "\n" (
            lib.concatLists (
              lib.mapAttrsToList (
                cluster: e:
                map (host: "    use_backend bk_http_${cluster} if { req.hdr(host),field(1,:) -i ${host} }") (
                  lib.unique e.hosts
                )
              ) routed
            )
          );

          backends = lib.concatStringsSep "\n\n" (
            lib.mapAttrsToList (
              cluster: e:
              let
                target =
                  if tls then
                    "${e.edge.backend}:${toString e.edge.httpsPort} ssl verify none"
                  else
                    "${e.edge.backend}:${toString e.edge.httpPort}";
              in
              ''
                backend bk_http_${cluster}
                    mode http
                    server srv1 ${target} init-addr none resolvers docker resolve-prefer ipv4''
            ) routed
          );
        in
        ''
          global
              log stdout format raw local0 info

          # `init-addr none` with a resolver, rather than resolving at startup:
          # the proxy comes up before the cluster it points at exists, and
          # HAProxy refuses to start on a server name it cannot resolve.
          resolvers docker
              nameserver dns1 127.0.0.11:53
              resolve_retries 30
              timeout resolve 1s
              timeout retry 1s
              hold valid 10s

          defaults
              timeout connect 5s
              timeout client ${inputs.idleTimeout}
              timeout server ${inputs.idleTimeout}
              timeout tunnel ${inputs.idleTimeout}
              log global

          ${
            if tls then
              ''
                frontend ft_https
                    bind *:443 ssl crt /etc/haproxy/certs/lab.pem
                    mode http

                ${routes}

                frontend ft_http
                    bind *:80
                    mode http

                    # Redirect to the bare host, not `redirect scheme https`,
                    # which keeps whatever port the client used and would send it
                    # to HTTPS on the HTTP port. Dropping the port lands on 443,
                    # which is what the zone's wildcard reaches.
                    http-request redirect location https://%[req.hdr(host),field(1,:)]%[path] code 301
              ''
            else
              ''
                frontend ft_http
                    bind *:80
                    mode http

                ${routes}
              ''
          }

          ${backends}
        '';
    in
    {
      out.routedHosts = lib.mapAttrs (_: e: lib.unique e.hosts) routed;

      provides.service =
        if backendless != [ ] then
          throw (
            "lab-proxy: the lab is asked to front "
            + lib.concatMapStringsSep ", " (c: "cluster '${c}'") backendless
            + ", whose provisioner answers no CLUSTER_EDGE — there is no address to route to."
            + " A cluster this lab did not create is reached at its own edge:"
            + " withhold its HOST_EXPOSURE export instead."
          )
        else
          {
            description = "HAProxy lab ingress (${requires.zone.zone})";
            container = containerName;
            inherit (inputs) image;

            command = [ ];

            ports = [
              "127.0.0.1:${toString httpPort}:80"
              "${network.gateway}:80:80"
            ]
            ++ lib.optionals tls [
              "127.0.0.1:${toString httpsPort}:443"
              "${network.gateway}:443:443"
            ];

            networks = [ network.name ];
            dnsContainers = [ ];

            readyProbe = {
              kind = "tcp";
              host = "127.0.0.1";
              port = httpPort;
              timeout = "60s";
            };

            volumes."/usr/local/etc/haproxy/haproxy.cfg".content = haproxyConfig;

            extraMounts = lib.optional tls {
              host = labCa.pem;
              container = "/etc/haproxy/certs/lab.pem";
            };
          };
    };
}
