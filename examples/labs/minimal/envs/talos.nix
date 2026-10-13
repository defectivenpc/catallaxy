# The minimal lab on Talos instead of k3d.
#
# One unit changes and no component does, which is the claim made about a
# provisioner, and the only way to find out whether it is true is to swap one.
# The platform, the workload and the apply are `clusters.app` untouched; what
# differs is three facts they read through `KUBERNETES_CLUSTER` and the lab's
# `edge`, not three branches anyone wrote here:
#
#   - nothing assigns LoadBalancer addresses, so the gateway asks for a
#     NodePort and waits on `Programmed` rather than on an address
#   - the lab's proxy dials that NodePort rather than the node's 80 and 443
#   - the proxy joins the cluster's own network, because talosctl will not
#     join the lab's
#
# It also makes `provenUnattended` in `nix/checks/e2e.nix` honest. That list
# has named Talos since it was written and nothing exercised it, so the half of
# `nix/checks/self-contained.nix` that covers Talos was pinning a claim about a
# provisioner no lab used.
{
  lab,
  floes,
  ...
}:

lab {
  name = "minimal.talos";

  units = {
    # On, unlike the rest of `minimal`. Without it nothing dials the cluster,
    # and the two things this lab exists to exercise — the proxy joining
    # Talos's own network, and dialing a NodePort rather than the node's 80 —
    # would both be inert.
    proxy = floes.lab-proxy { };
    egress = floes.lab-egress { };

    # One root for the lab: the ingress serves from it, and any cluster that
    # declares `optional.labCa` signs from it rather than minting a second.
    # Placing it is the whole decision — it was `lab.proxy.tls.enable`, an
    # option defaulting to true that no lab ever set.
    ca = floes.lab-ca { };

    # The registry mounts `registries.yaml` and a CA into every node, and the
    # provisioner is what does the mounting. Talos takes machine config rather
    # than bind mounts, so `talos-cluster` declares no `OCI_MIRROR` hole and
    # there is no path for the file to arrive on.
    #
    # Left in, the cache would run, answer, and be consulted by nothing — which
    # the lab refuses by name now rather than leaving to this paragraph. `null`
    # withdraws what `lab.nix` placed.
    registry = null;
  };

  claim = floes.talos-cluster {
    # Must not overlap the lab's own network, and no check covers it: this
    # network is talosctl's, not one the lab creates, so `lab-subnets` never
    # sees it.
    subnet = "10.7.0.0/24";
  };
}
