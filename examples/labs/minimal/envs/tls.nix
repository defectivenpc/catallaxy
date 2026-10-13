# The minimal lab, serving https from a CA the lab mints itself.
#
# An environment is the same lab with different settings, which is exactly what
# this is: one input value and four host services. `minimal.local` stays plain
# HTTP, so the two run side by side and a change that breaks the untrusted path
# is still caught.
#
# It used to add `coredns-zone` and `trust-manager` to the cluster and
# `mkForce` two of its floes. Those four floes are `standard-cluster`'s, so the
# environment says what differs and the platform does the rest — and what
# differs is one input and four units, because signing from the lab's root is
# the cluster resolving `LAB_CA` rather than a second boolean.
{
  lab,
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ../clusters.nix { inherit catallaxy floes lib; };
in
lab {
  name = "minimal.tls";

  # trust-manager then puts the lab's root in a ConfigMap in every namespace,
  # so a workload can verify what the lab signed.
  cluster = clusters.app { tls = true; };

  units = {
    # The host half: a resolver that answers for the zone, and an ingress that
    # terminates TLS with the root below.
    dns = floes.lab-dns { };
    proxy = floes.lab-proxy { };
    egress = floes.lab-egress { };

    # One root, and the lab holds it. `cert-generate` writes the certificate
    # HAProxy serves from and the CLI seeds the root as every cluster issuer's
    # backing Secret — so a cluster that resolves this must not mint a second
    # one over the top, and resolving it is what stops it.
    #
    # Placing it is the whole decision. It was `lab.proxy.tls.enable`, an
    # option defaulting to true that no lab ever set, plus `rootFromLab` on the
    # cluster that had to agree with it.
    ca = floes.lab-ca { };
  };

  # There is an ingress now, so every route the clusters expose must answer
  # through it. This is the lab that proves the whole path.
  verifyEndpoints.enable = true;
}
