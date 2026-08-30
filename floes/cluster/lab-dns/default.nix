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
# lab holds — the zone and where its server answers — and those are inputs.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "lab-dns";

  inputs = {
    zone = lib.mkOption {
      type = lib.types.str;
      description = "The lab's DNS zone. Required; pass `config.lab.dns.zone`.";
    };

    server = lib.mkOption {
      type = lib.types.str;
      description = ''
        Address the lab's DNS answers on, as seen from inside the cluster.
        Required; pass `config.lab.dns.server`.

        The docker bridge gateway rather than loopback: `127.0.0.1` inside a
        pod is the pod.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5354;
      description = "Port the lab's DNS answers on. Pass `config.lab.dns.port`.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kube-system";
      description = "Namespace CoreDNS runs in, and so where the ConfigMap has to be.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        serverBlock = ''
          ${inputs.zone}:53 {
              errors
              cache 30
              forward . ${inputs.server}:${toString inputs.port}
          }
        '';
      in
      {
        config.floe.out.component = kinds.mkComponent {
          # Nothing else needs to wait on a ConfigMap, and there is no
          # workload here to be ready.
          imagesComplete = true;

          network = {
            declared = true;
            egress.cidrs = [
              {
                # CoreDNS dialling the lab's resolver. Not `internet`: the
                # address is on the lab's own bridge.
                cidr = "0.0.0.0/0";
                ports = [
                  {
                    port = inputs.port;
                    protocol = "UDP";
                  }
                  {
                    port = inputs.port;
                    protocol = "TCP";
                  }
                ];
              }
            ];
          };

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
