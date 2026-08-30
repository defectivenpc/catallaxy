# The lab's ingress: HAProxy in front of every cluster's gateway.
#
# This is what makes a hostname mean something. The zone's wildcard points at
# the docker bridge gateway, this listens there, and it routes by Host header
# to whichever cluster declared the route.
#
# Terminate-only. The parked proxy also did SNI passthrough for an internal
# tier reached over a mesh; the current gateway floe has neither, and a mode
# with no way to select it is a branch nothing tests.
{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  cfg = config.lab.proxy;

  # Every publicly routed hostname, with the cluster that serves it. The
  # elaborator already read these off the rendered routes, so there is no list
  # to keep in step with the manifests.
  exposed = lib.concatLists (
    lib.mapAttrsToList (
      clusterName: c:
      map (h: {
        inherit clusterName;
        inherit (h) host bundle;
        inherit (c.ingress) backend httpPort httpsPort;
      }) (lib.filter (h: h.tier == "public") c.out.exposedHosts)
    ) config.lab.clusters
  );

  hosts = lib.unique (map (e: e.host) exposed);

  # A route whose cluster cannot say where to send traffic would render a
  # backend pointing at nothing, and every request through it would time out
  # with no indication why.
  backendless = lib.unique (
    map (e: "cluster '${e.clusterName}' routes '${e.host}' but has no ingress backend") (
      lib.filter (e: e.backend == null) exposed
    )
  );

  routedClusters = lib.unique (map (e: e.clusterName) (lib.filter (e: e.backend != null) exposed));

  clusterOf = name: lib.head (lib.filter (e: e.clusterName == name) exposed);

  haproxyConfig =
    let
      # `field(1,:)` drops the port before matching. A client reaching a lab
      # on anything but 80/443 sends `Host: name:8443`, which an exact match
      # on the bare name misses — and the symptom is a 503 from the ingress
      # rather than anything naming the header. Non-default ports are the
      # normal case as soon as a second lab shares the host.
      routes = lib.concatMapStringsSep "\n" (
        e: "    use_backend bk_http_${e.clusterName} if { req.hdr(host),field(1,:) -i ${e.host} }"
      ) (lib.filter (e: e.backend != null) exposed);

      backends = lib.concatMapStringsSep "\n\n" (
        name:
        let
          e = clusterOf name;
          target =
            if cfg.tls.enable then
              "${e.backend}:${toString e.httpsPort} ssl verify none"
            else
              "${e.backend}:${toString e.httpPort}";
        in
        ''
          backend bk_http_${name}
              mode http
              server srv1 ${target} init-addr none resolvers docker resolve-prefer ipv4''
      ) routedClusters;
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
          timeout client ${cfg.idleTimeout}
          timeout server ${cfg.idleTimeout}
          timeout tunnel ${cfg.idleTimeout}
          log global

      ${
        if cfg.tls.enable then
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
  options.lab.proxy = {
    enable = mkEnableOption "an HAProxy ingress in front of the clusters' gateways";

    tls = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Terminate TLS with the lab's own CA, and redirect plain HTTP to it.

          The certificate is minted by the `cert-generate` step, which is
          emitted only when this is on. It is also what puts a CA on disk for
          the cluster's issuer to sign from, so turning this off leaves the
          lab with no root at all.
        '';
      };
    };

    idleTimeout = mkOption {
      type = types.str;
      default = "1h";
      description = ''
        How long an idle connection is held open.

        Long, deliberately. HAProxy's defaults are tens of seconds, which
        orderly-closes the long-lived streams that gRPC and watch-based
        clients keep open — and the symptom is not a failure but a client
        that silently reconnects forever.
      '';
    };

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "Loopback port the HTTP listener is published on.";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "Loopback port the HTTPS listener is published on.";
    };

    image = mkOption {
      type = types.str;
      default = "haproxy:3.1-alpine";
      description = "HAProxy container image.";
    };

    containerName = mkOption {
      type = types.str;
      default = "catallaxy-${config.lab.name}-ingress";
      defaultText = lib.literalExpression ''"catallaxy-''${config.lab.name}-ingress"'';
      description = "Docker container name for the ingress.";
    };

    out = {
      service = mkOption {
        type = types.attrs;
        readOnly = true;
        description = "The `HostService` record `setup-services` starts.";
      };

      hosts = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        description = "Every hostname this ingress answers for.";
      };
    };
  };

  config.lab.assertions = lib.optionals cfg.enable (
    map (message: {
      assertion = false;
      inherit message;
    }) backendless
  );

  config.lab.proxy.out = mkIf cfg.enable {
    hosts = hosts;

    service = {
      description = "HAProxy lab ingress (${config.lab.dns.zone})";
      container = cfg.containerName;
      inherit (cfg) image;

      # Published twice on purpose. Loopback is where a human reaches it; the
      # bridge gateway is what the zone's wildcard answers, and so what
      # everything inside the lab reaches it on. Only the second is reachable
      # from a pod, and only the first from a browser with no DNS setup.
      ports = [
        "127.0.0.1:${toString cfg.httpPort}:80"
        "${config.lab.dns.server}:80:80"
      ]
      ++ lib.optionals cfg.tls.enable [
        "127.0.0.1:${toString cfg.httpsPort}:443"
        "${config.lab.dns.server}:443:443"
      ];

      readyProbe = {
        kind = "tcp";
        host = "127.0.0.1";
        port = cfg.httpPort;
        timeout = "60s";
      };

      volumes."/usr/local/etc/haproxy/haproxy.cfg".content = haproxyConfig;

      # `{{STATE_DIR}}` is expanded by the CLI. The file is the concatenated
      # cert and key that `cert-generate` writes.
      extraMounts = lib.optional cfg.tls.enable {
        host = "{{STATE_DIR}}/proxy/lab.pem";
        container = "/etc/haproxy/certs/lab.pem";
      };

      networks = [ config.lab.name ];
    };
  };
}
