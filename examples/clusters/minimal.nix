# One cluster, closed, with no lab around it.
#
# Every other fixture in the tree is a lab. This one is the thing a lab used
# to be the only way to write: a cluster that answers everything it needs, so
# nothing has to fill a hole for it. `cata cluster up --from-file` acts on
# exactly this, and `cluster-artifact-standalone-minimal` reads it back.
#
# What it demonstrates is closure, and closure is now something you can read
# in the header rather than something you work out from a list. A gateway
# needs `DNS_ZONE`, which is usually a fact the lab holds and hands down — so
# a cluster with a gateway and no zone of its own is a *component*. This one
# holds its own `lab-zone` inside, which is why `requires` names only the
# claim: every other hole is answered in here.
#
# The claim stays open even so. A closed cluster is one with no hole a *lab*
# would fill, and the thing that brings a cluster into existence is not a lab
# — it is the provisioner beside it, which is what `cluster.claim` is.
{
  floes,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  floe = mkClusterFloe {
    name = "standalone-minimal";
    summary = "A cluster that answers its own zone, so nothing outside it has to.";

    requires.claim = sigs.KUBERNETES_CLUSTER;

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "kapp/delivery";

    units = _: {
      # Said rather than defaulted: `cata` applies this cluster, and one
      # that answers nothing is refused rather than quietly applied by hand.
      kapp = floes.kapp { };

      # Its own zone, which is the hole a lab would otherwise fill. Holding
      # it here is the whole of what makes this closed.
      #
      # And its own network, because the zone's server address is a network
      # fact: the zone resolves `LAB_NETWORK` rather than taking an address,
      # so a cluster standing in for a lab stands in for both. `managed` is
      # false — there is no lab here to create a docker network, and a
      # `docker network create` in a standalone cluster's plan would be a step
      # about something nothing owns.
      network = floes.lab-network {
        name = "standalone";
        subnet = "127.0.0.0/8";
        managed = false;
      };

      zone = floes.lab-zone { zone = "standalone.test"; };

      gateway-api = floes.gateway-api-crds { };
      cert-manager = floes.cert-manager { };
      gateway = floes.gateway { };
      podinfo = floes.podinfo { };
    };
  } { };

  claim = floes.k3d-cluster {
    name = "standalone";
    instanceName = "standalone-minimal";
  };
}
