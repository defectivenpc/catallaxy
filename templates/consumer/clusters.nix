# Your cluster, as a floe.
#
# This is the file worth reading twice. Everything above `units` is the
# cluster's *interface*: what it needs of whatever places it, what it offers
# back, and which unit each offer comes from. A reader learns all of that
# without evaluating anything, which is the property the whole floe interface
# exists for — and the reason a cluster is authored here rather than assembled
# out of an option tree in `lab.nix`.
#
# Both holes are open on purpose:
#
#   - `claim`, because a cluster floe is not the thing that creates a
#     cluster. Leaving it open is what lets this same cluster run on k3d
#     here and on Talos or a managed cluster elsewhere, with no component
#     inside changing — they resolve against the hole, never against the
#     thing that fills it.
#   - `zone`, because the DNS zone is a fact the lab holds and no cluster
#     can derive.
#
# `mkClusterFloe` is `floe.mkFloe` with this distribution's cluster policies
# already on it, and callable so `clusters.app { }` reads like
# `floes.podinfo { }`.
{
  catallaxy,
  floes,
  myFloes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  app = mkClusterFloe {
    name = "my-platform-app";
    summary = "A platform behind a gateway, and one workload of my own.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    # The one thing a lab needs of a cluster that only the cluster can say:
    # how its content reaches it. The lab finds it by signature off this
    # boundary rather than by reaching into the units, because an inclusion
    # seals — add a floe inside and nothing outside can see it unless you say
    # so here.
    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "kapp/delivery";

    units = _: {
      # How this cluster's content reaches it. `cata` applies, which is what
      # most clusters want; a CD tool answering the same signature is what
      # takes that over, and holding both is refused by name.
      kapp = floes.kapp { };

      gateway-api = floes.gateway-api-crds { };

      # The gateway requires X509_ISSUANCE outright, so every cluster with a
      # gateway has an issuer even when nothing terminates TLS.
      cert-manager = floes.cert-manager { };

      gateway = floes.gateway { };

      hello = myFloes.hello-world { };
    };
  };
}
