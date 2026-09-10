# The minimal lab with cilium instead of flannel.
#
# Exists to boot a CNI, which is the one thing rendering cannot check: the
# bootstrap manifest is a derivation the lab hands to the provisioner, and a
# node stays NotReady until k3s has applied it. Nothing short of starting one
# tells you whether that happens.
#
# It also gives the network-policy work a cluster that enforces a
# NetworkPolicy. k3s ships flannel, which implements none — a policy applied
# to `minimal.local` is admitted, stored, and enforced by nothing.
{
  lib,
  cataCharts,
  floes,
  ...
}:
{
  lab.name = "minimal.cilium";

  lab.network.subnet = "172.33.0.0/16";
  lab.proxy.httpPort = 8083;
  lab.proxy.httpsPort = 8446;
  lab.dns.hostPort = 5359;
  lab.registry.port = 5055;
  lab.egress.port = 3132;

  lab.clusters.app.floes = {
    # Both halves. `disableFlannel` alone leaves nodes that never become
    # Ready; the manifest alone leaves a cluster carrying two CNIs, each
    # writing its own datapath rules over the other's.
    cluster = lib.mkForce (
      floes.k3d-cluster {
        name = "app";
        instanceName = "minimal-cilium-app";

        disableFlannel = true;
        autoDeployManifests = [
          {
            name = "cilium";
            path = "${floes.cilium.mkBootstrapManifest { chart = "${cataCharts.cilium.chart}"; }}";
          }
        ];
      }
    );

    # The same chart again, as a release that takes ownership once the cluster
    # is up, so upgrades and drift work like any other floe's.
    cilium = floes.cilium { chart = "${cataCharts.cilium.chart}"; };
  };
}
