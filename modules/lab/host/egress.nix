# A forward proxy inside the lab network.
#
# The lab's names resolve through the lab's DNS, which the host does not use
# unless `lab.dns.configureHost` is on — and that needs sudo. This is the way
# to reach a lab hostname from a host tool without touching the host's
# resolver: point the tool at `http://127.0.0.1:3128` and let something inside
# the network do the resolving.
{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  cfg = config.lab.egress;

  # `Allow 0.0.0.0/0` is safe only because the port is published on loopback
  # and nowhere else; anything that can reach it can already reach the lab.
  tinyproxyConfig = ''
    Port 8888
    Listen 0.0.0.0
    Timeout 600
    Allow 0.0.0.0/0
    ConnectPort 443
    ConnectPort 80
    LogLevel Info
  '';
in
{
  options.lab.egress = {
    enable =
      mkEnableOption "a forward proxy inside the lab network, so host tools can reach lab hostnames"
      // {
        default = config.lab.proxy.enable;
        defaultText = lib.literalExpression "config.lab.proxy.enable";
      };

    port = mkOption {
      type = types.port;
      default = 3128;
      description = "Loopback port the forward proxy is published on.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/querateam/docker-tinyproxy:latest";
      description = "tinyproxy container image.";
    };

    containerName = mkOption {
      type = types.str;
      default = "catallaxy-${config.lab.name}-egress";
      defaultText = lib.literalExpression ''"catallaxy-''${config.lab.name}-egress"'';
      description = "Docker container name for the forward proxy.";
    };

    out.service = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "The `HostService` record `setup-services` starts.";
    };
  };

  config.lab.egress.out = mkIf cfg.enable {
    service = {
      description = "Forward proxy inside the lab network (${config.lab.dns.zone})";
      container = cfg.containerName;
      inherit (cfg) image;
      ports = [ "127.0.0.1:${toString cfg.port}:8888" ];

      volumes."/etc/tinyproxy/tinyproxy.conf".content = tinyproxyConfig;

      networks = [ config.lab.name ];

      # The one service that resolves through the lab's DNS rather than
      # docker's, which is the whole reason it exists.
      dnsContainers = lib.optional config.lab.dns.enable config.lab.dns.containerName;
    };
  };
}
