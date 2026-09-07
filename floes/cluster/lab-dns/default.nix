# Teach the cluster's CoreDNS about the lab's zone.
#
# The host resolves `*.<zone>` through the lab's DNS server. A pod does not:
# its resolver is the cluster's CoreDNS, which knows about `cluster.local` and
# forwards everything else upstream — and upstream has never heard of the lab.
# So a workload calling another workload by its public hostname fails on a
# name that resolves perfectly well from the host.
#
# This is one ConfigMap that adds a server block for the zone. k3s's CoreDNS
# mounts `coredns-custom` and imports `/etc/coredns/custom/*.server`, so the
# only thing needed is to put the file there.
#
# A floe rather than a cluster module because it needs exactly two facts the
# lab holds — the zone and where its server answers — and the lab provides
# them: `requires.zone = DNS_ZONE`, resolved from lab scope.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "lab-dns";
  summary = "A CoreDNS override teaching the cluster to resolve the lab's zone.";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kube-system";
      description = "Namespace CoreDNS runs in, and so where the ConfigMap has to be.";
    };
  };

  # The zone, the server and the port, from whoever holds them — which in a
  # lab is the lab. These were three inputs the caller threaded in by hand,
  # and `external-dns` took the same three, so a lab had six arguments to keep
  # consistent and nothing checking that it had.
  requires.zone = sigs.DNS_ZONE;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        zone = config.floe.requires.zone;

        serverBlock = ''
          ${zone.zone}:53 {
              errors
              cache 30
              forward . ${zone.server}:${toString zone.port}
          }
        '';
      in
      {
        config.floe.out.component = kinds.mkComponent {
          # Nothing else needs to wait on a ConfigMap, and there is no
          # workload here to be ready.
          imagesComplete = true;

          bundles.coredns = kinds.mkBundle {
            resources.coredns-custom = {
              apiVersion = "v1";
              kind = "ConfigMap";
              metadata = {
                name = "coredns-custom";
                inherit (inputs) namespace;
              };
              data."lab.server" = serverBlock;
            };

            # A ConfigMap is ready when it exists; CoreDNS picks it up on its
            # own schedule and there is no status to wait on.
            awaitRollout = false;
          };
        };
      }
    )
  ];
}
