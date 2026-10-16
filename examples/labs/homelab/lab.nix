# Two clusters, standing up together.
#
# The first lab in the tree with more than one cluster that actually runs.
# `secret-sharing` has two and never runs; every other lab has one. What this
# proves is the whole of the multi-cluster lifecycle: one docker network, one
# resolver and one ingress in front of two gateways, two kubeconfigs, and a
# plan that interleaves both clusters' waves.
#
# It is also the only runnable lab with an identity provider in it, so the
# OIDC path — kanidm minting a client that forgejo and harbor each render for
# themselves — is exercised for real rather than only rendered.
#
# ## The split
#
# `core` is the platform: identity, source control, a registry, trust,
# routing, backups. `obs` is observability: metrics, logs, traces and a
# dashboard over them.
#
# ## What it deliberately does not do
#
# **No cross-cluster telemetry.** `core` does not ship its metrics to `obs`.
# It could only do so by naming `obs`'s Prometheus, and a floe reads its
# backends through `METRICS_INGEST`, which resolves within a cluster — RFC
# 0005 §3.1. The parked lab wrote the URL out by hand on both sides; deriving
# it from the zone would work and would also be the first place in the tree
# where one cluster's configuration depended on another's by convention. That
# is an open question and it is not settled here.
#
# **No OIDC on `obs`'s Grafana.** Same reason, and it is the sharper case: the
# hole is right there on the floe, `optional.oidc`, and kanidm is one
# cluster away where nothing can reach it.
#
# **No Argo.** `argocd` provides `DELIVERY_POLICY`, which is a lab-wide
# decision, and the root Application it produces points
# at exactly one cluster's manifests. A two-cluster gitops lab is therefore a
# shape nobody has run, and inventing it here would test two new things at
# once. `gitops.local` covers delivery; this covers two clusters.
#
# **No external-dns.** The zone's wildcard already answers for everything the
# ingress routes, so a DNS controller has nothing to add — and the floe wants
# a TSIG key matching `lab.dns.tsigSecret`, which no lab has a way to project
# without writing the same value in two places.
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
