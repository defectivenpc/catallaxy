# A lab that is not the edge for one of its clusters.
#
# Until RFC 0005 §6.4 this was inexpressible. The lab assumed the operator's
# machine fronted every cluster, in four places, and the first of them was an
# assertion — so a cluster that routed a hostname and named no backend did not
# render badly, it failed `nix eval`. That is exactly the shape of a managed
# cluster in a cloud, which has a LoadBalancer of its own and an address the
# lab does not assign.
#
# `core` is fronted by the lab, the way every shipped cluster is. `edge` is
# its own edge. Both route a public hostname, and what this pins is that the
# lab says nothing about the second one's:
#
#   - the proxy renders a backend for `core` and none for `edge`
#   - `lab-routed-hosts-are-proxied` does not fire for `edge`
#   - `cliConfig-self-edge` carries `mode: "self"`, so `cata lab verify` can
#     tell the two apart and stops resolving every routed host to loopback
#
# The mode is forced onto a k3d cluster rather than taken from a cloud
# provisioner floe, because none is built yet and the lab-side half is what
# this covers. A provisioner that answers `self` for real changes which floe
# is instantiated here and nothing else — which is the claim (RFC 0005 §8.2).
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  ...
}:

let
  common = clusterName: {
    cluster = floes.k3d-cluster {
      name = clusterName;
      instanceName = "self-edge-${clusterName}";
      podSubnet = if clusterName == "core" then "10.244.0.0/16" else "10.245.0.0/16";
      serviceSubnet = if clusterName == "core" then "10.96.0.0/12" else "10.112.0.0/12";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };

    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
    };

    # The same app, at the same hostname, in both clusters. A route's name
    # comes from the lab's one zone, so this is not a choice — but it is also
    # the real arrangement a self-edge cluster exists for: the lab serves the
    # name locally and something else serves it elsewhere. It is what makes
    # `lab-routed-hosts-are-unique` interesting here (see the check).
    podinfo = floes.podinfo { };
  };
in
{
  lab.name = "self-edge";
  lab.dns.zone = "self-edge.test";

  # The proxy is on, which is the point: a lab with no proxy would pass this
  # by having nothing to route rather than by routing the right subset.
  lab.proxy.enable = true;
  lab.network.subnet = "172.40.0.0/16";
  lab.proxy.httpPort = 8090;
  lab.dns.hostPort = 5370;

  lab.clusters.core.floes = common "core";

  lab.clusters.edge.floes = common "edge";

  # `mkForce`, because the k3d floe answers `proxy` and means it. A lab
  # overriding this is stating something about the arrangement the floe
  # cannot know — here, that something other than this lab reaches the
  # cluster. RFC 0005 §6.4 calls `self` a refusal to route rather than a
  # deferred address, and this is what refusing looks like.
  lab.clusters.edge.edge.mode = lib.mkForce "self";
}
