# The minimal lab on Talos instead of k3d.
#
# One instantiation changes and no member does, which is the claim RFC 0005
# §8.2 makes about the provisioner and the only way to find out whether it is
# true is to swap one. The gateway, cert-manager, the CRDs and podinfo below
# are inherited from `lab.nix` untouched; what differs is three facts they
# read through `KUBERNETES_CLUSTER` and the lab's `edge`, not three branches
# anyone wrote here:
#
#   - nothing assigns LoadBalancer addresses, so the gateway asks for a
#     NodePort and waits on `Programmed` rather than on an address
#   - the lab's proxy dials that NodePort rather than the node's 80 and 443
#   - the proxy joins the cluster's own network, because talosctl will not
#     join the lab's
#
# It also makes `provenUnattended` in `modules/lab/e2e.nix` honest. That list
# has named Talos since it was written and nothing exercised it, so the half
# of `nix/checks/self-contained.nix` that covers Talos was pinning a claim
# about a provisioner no lab used.
{
  lib,
  floes,
  ...
}:
{
  lab.name = "minimal.talos";

  # On, unlike the rest of `minimal`. Without it nothing dials the cluster,
  # and the two things this lab exists to exercise — the proxy joining
  # Talos's own network, and dialing a NodePort rather than the node's 80 —
  # would both be inert.
  lab.proxy.enable = true;

  # Its own ports and network, so it runs beside the k3d labs rather than
  # instead of them. Note this is the *lab's* network; Talos makes a second
  # one of its own that talosctl controls and the lab's checks do not see.
  lab.network.subnet = "172.37.0.0/16";
  lab.proxy.httpPort = 8087;
  lab.proxy.httpsPort = 8450;
  lab.dns.hostPort = 5363;
  lab.registry.port = 5059;
  lab.egress.port = 3136;

  # The registry mounts `registries.yaml` and a CA into every node, and the
  # provisioner is what does the mounting. Talos takes machine config rather
  # than bind mounts, so that path is not built — and a lab that pulled
  # through a mirror the nodes cannot see would fail on every image with a
  # DNS error, which is a worse way to find out than this.
  lab.registry.enable = lib.mkForce false;

  lab.clusters.app.floes.cluster = lib.mkForce (
    floes.talos-cluster {
      name = "app";
      instanceName = "minimal-talos-app";

      # Must not overlap the lab's own network above, and no check covers it:
      # this network is talosctl's, not one the lab creates, so
      # `lab-subnets` never sees it.
      subnet = "10.7.0.0/24";
    }
  );
}
