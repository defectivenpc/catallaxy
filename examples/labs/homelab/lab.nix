# Two clusters, standing up together.

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
  name = "homelab";
  summary = "Two clusters, standing up together.";

  inputs = {
    # The zone is `clusters.nix`'s, because that is the file that derives
    # hostnames from it.
    zone.default = clusters.zone;

    core = lib.mkOption {
      type = catallaxy.floeInstance;
      default = clusters.core { };
      defaultText = lib.literalExpression "clusters.core { }";
      description = ''
        The platform cluster: identity, source control, a registry, trust,
        routing and backups.

        An instance, so an environment is a different cluster rather than this
        one with a flag — `homelab.mesh`'s `core` runs a mesh and holds a
        store, and `homelab.dns`'s publishes records for what it routes.
      '';
    };

    obs = lib.mkOption {
      type = catallaxy.floeInstance;
      default = clusters.obs { };
      defaultText = lib.literalExpression "clusters.obs { }";
      description = "The observability cluster: metrics, logs, traces and a dashboard over them.";
    };
  };

  units = _: {
    # All three host services. The resolver answers for the zone, the ingress
    # routes by Host header to whichever cluster declared the route, and the
    # registry caches what two clusters would otherwise pull twice.
    dns = floes.lab-dns { };
    proxy = floes.lab-proxy { };
    egress = floes.lab-egress { };

    # One root for the lab: the ingress serves from it, and any cluster that
    # declares `optional.labCa` signs from it rather than minting a second.
    # Placing it is the whole decision — it was `lab.proxy.tls.enable`, an
    # option defaulting to true that no lab ever set.
    ca = floes.lab-ca { };

    registry = floes.lab-registry { };
  };

  # Two clusters on one docker network, so their pod and service ranges have to
  # be told apart: an address plan is a decision written down, not something
  # derived from the cluster's name, where a rename would silently move a
  # running cluster's subnet.
  clusters =
    { inputs, ... }:
    {
      core = {
        floe = inputs.core;
        provisioner = floes.k3d-cluster {
          podSubnet = "10.244.0.0/16";
          serviceSubnet = "10.96.0.0/12";
        };
      };

      obs = {
        floe = inputs.obs;
        provisioner = floes.k3d-cluster {
          podSubnet = "10.245.0.0/16";
          serviceSubnet = "10.112.0.0/12";
        };
      };
    };
}
