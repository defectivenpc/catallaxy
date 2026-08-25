# k3d-local, ported to the floe interface at lab scope.
#
# Spike artefact, beside ./k3d-local.nix. This is the half the spike had not
# touched, and the one that felt sketchy — because in the shape as shipped it
# *is* sketchy: `modules/lab/lab-floe-options.nix` is a second, hand-copied
# interface declaring `options.lab.floes.<name>` at a dynamic path, six of
# whose seven channels are the cluster interface's channels written out again.
#
# Under `lib/floe/interface.nix` there is no second interface. A lab floe is
# the same class as a cluster floe — same `_class`, same registry, same
# `exports`/`peers`/`capabilities`/`assertions` — differing only in which
# extension is merged in. Compare the two files:
#
#   cluster floe:  extensions = [ clusterExtension ]  -> bundles, namespace,
#                                                        images, network, …
#   lab floe:      extensions = [ labExtension ]      -> clusters, labConfig,
#                                                        lab-scope steps
#
# and `floes/cluster/reloader/modular.nix` and this file are recognisably the
# same kind of thing, which `floes/cluster/reloader/default.nix` and
# `floes/lab/k3d-local.nix` are not.
#
# The one real difference from the cluster port: a lab floe's writes go to
# `labConfig` rather than to `lab.*` directly, for the same reason a cluster
# floe's go to `ingress` rather than `cluster.ingress` — a floe is no longer
# evaluated inside the tree it is configuring. See the note on `labConfig` in
# `lib/floe/lab.nix` for why that channel is `types.attrs` and where the type
# checking actually happens.
{
  config,
  lib,
  lab ? { },
  ...
}:

let
  inherit (lib) mkOption types;

  # A lab *read*, through the same channel a cluster floe reads `cluster`
  # facts through. The original reaches into `config.lab.platforms` directly,
  # which it can only do because it is evaluated inside the lab's tree; here
  # the lab arrives as a framework value, so the read is explicit and the
  # write half (`labConfig`) is a separate, declared channel.
  contested = lab.platforms.contestedClusters or [ ];
in
{
  options = {
    image = mkOption {
      type = types.nullOr types.str;
      default = "rancher/k3s:v1.31.4-k3s1";
      description = "k3s image k3d runs. Null takes k3d's own default, which moves when k3d does.";
    };

    network = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Docker network the clusters join, where this platform means to move
        them off the lab's own.

        Null leaves `provisioner.k3d.network` alone, and that already defaults
        to the lab's network, which is where its DNS, registry and ingress
        are. Saying it twice is how the two come to disagree.
      '';
    };

    dockerSubnet = mkOption {
      type = types.str;
      default = "172.20.0.0/16";
      description = "Subnet for the lab's docker network.";
    };

    tls = mkOption {
      type = types.bool;
      default = true;
      description = "Whether the lab's proxy terminates TLS.";
    };

    hostPorts = {
      proxy = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port for the lab proxy. Null keeps the lab's default.";
      };
      registry = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port for the lab registry. Null keeps the lab's default.";
      };
      egress = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port for lab egress. Null keeps the lab's default.";
      };
      dns = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port for lab DNS. Null keeps the lab's default.";
      };
    };

    # Extends the interface's empty `exports` submodule, exactly as a cluster
    # floe does. That this line is identical in kind to reloader's is the
    # point: `exports` is a base channel, not a per-scope one.
    exports = mkOption {
      type = types.submodule {
        options.clusters = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Clusters this platform stood up, for a floe layered on top to reach the same set.";
        };
      };
    };
  };

  config = lib.mkIf config.enable {
    exports.clusters = config.clusters;

    # This platform does the `kubernetes-cluster` job. Nothing reads it yet at
    # lab scope, but declaring it is what lets a floe layered on top say
    # `dependencies.platform.capability = "kubernetes-cluster"` rather than
    # naming k3d-local and refusing to work on talos.
    capabilities.provides.kubernetes-cluster = {
      provisioner = "k3d";
      clusters = config.clusters;
    };

    labConfig = {
      network.dockerSubnet = lib.mkDefault config.dockerSubnet;

      dns.enable = lib.mkDefault true;
      registry.enable = lib.mkDefault true;
      proxy.enable = lib.mkDefault true;
      proxy.tls.enable = lib.mkDefault config.tls;

      proxy.httpPort = lib.mkIf (config.hostPorts.proxy != null) (lib.mkDefault config.hostPorts.proxy);
      registry.port = lib.mkIf (config.hostPorts.registry != null) (
        lib.mkDefault config.hostPorts.registry
      );
      egress.port = lib.mkIf (config.hostPorts.egress != null) (lib.mkDefault config.hostPorts.egress);
      dns.hostPort = lib.mkIf (config.hostPorts.dns != null) (lib.mkDefault config.hostPorts.dns);

      clusters = lib.genAttrs (lib.subtractLists contested config.clusters) (_: {
        cluster.provisioner = lib.mkDefault "k3d";

        provisioner.k3d = {
          image = lib.mkDefault config.image;
          network = lib.mkIf (config.network != null) (lib.mkDefault config.network);

          noTraefik = lib.mkDefault true;
          noServiceLB = lib.mkDefault false;
        };
      });
    };
  };
}
