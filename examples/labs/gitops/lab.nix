# One cluster, handed over to Argo CD.
#
# The lab `cata` applies least: `argocd` answers `DELIVERY_POLICY`, so the
# plan bootstraps Argo and points it at the repository the cluster exports,
# and everything after that is Argo's.
#
# It declares no inputs of its own, because its one environment varies nothing.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters.nix { inherit catallaxy floes lib; };
in
catallaxy.mkLabFloe {
  name = "gitops";
  summary = "One cluster, handed over to Argo CD.";

  inputs.zone.default = "gitops.test";

  units = _: {
    registry = floes.lab-registry { };

    # The whole path: a resolver for the zone and an ingress terminating TLS in
    # front of forgejo, Argo and podinfo.
    dns = floes.lab-dns { };
    proxy = floes.lab-proxy { };
    egress = floes.lab-egress { };

    # One root for the lab: the ingress serves from it, and any cluster that
    # declares `optional.labCa` signs from it rather than minting a second.
    # Placing it is the whole decision — it was `lab.proxy.tls.enable`, an
    # option defaulting to true that no lab ever set.
    ca = floes.lab-ca { };
  };

  clusters = _: {
    app = {
      floe = clusters.app { };
      provisioner = floes.k3d-cluster { };
    };
  };
}
