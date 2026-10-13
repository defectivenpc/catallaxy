# One cluster that provisions another, and the one it provisions.
#
# `mgmt` holds a `provisions-cluster` floe and *exports* what it provides, so
# `workload` resolves `CLUSTER_PROVISIONING` across the boundary. That export
# is the whole of the mechanism: a cluster names what another cluster may
# read, in the signature the boundary allows, and the lab's `defaults` say
# which cluster an optional hole means.
#
# It used to be `lab.clusters.mgmt.provides = [ "provisions-workload/provisioning" ]`
# and a table that mapped the signature to a narrower form. The boundary
# declares both now.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;

  platform = {
    kapp = floes.kapp { };
    gateway-api = floes.gateway-api-crds { };
    cert-manager = floes.cert-manager { };
    gateway = floes.gateway { };
  };
in
{
  mgmt = mkClusterFloe {
    name = "provisions-mgmt";
    summary = "A cluster that brings another into existence through a managed resource.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    provides = {
      delivery = sigs.DELIVERY_POLICY;
      provisioning = sigs.CLUSTER_PROVISIONING;
    };

    exports = {
      delivery = "kapp/delivery";
      provisioning = "provisions-workload/provisioning";
    };

    units =
      _:
      platform
      // {
        provisions-workload = floes.provisions-cluster {
          resourceKind = "clusters.kubernetes.digitalocean.crossplane.io";
          resourceName = "workload";
        };
      };
  };

  # Its own edge, which it says by exporting no exposure. Nothing in this lab
  # created it, so there is no container for the ingress to dial and no
  # address the lab can derive — the same arrangement `cloud`'s workload is
  # in, for the same reason.
  workload = mkClusterFloe {
    name = "provisions-workload";
    summary = "The cluster `mgmt` provisions, with a workload behind a gateway.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "kapp/delivery";

    units =
      _:
      platform
      // {
        podinfo = floes.podinfo { };
      };
  };
}
