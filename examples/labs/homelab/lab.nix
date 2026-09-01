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
# is open question 3 of RFC 0005 and it is not settled here.
#
# **No OIDC on `obs`'s Grafana.** Same reason, and it is the sharper case: the
# hole is right there on the floe, `requiresOptional.oidc`, and kanidm is one
# cluster away where nothing can reach it.
#
# **No Argo.** `argocd` provides `DELIVERY_POLICY`, which is a lab-wide
# decision (`modules/lab/cd.nix`), and the root Application it produces points
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
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:

let
  zone = config.lab.dns.zone;

  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";

  # What both clusters need before anything in them can be reached: the CRDs
  # the gateway is written against, a root to sign from, a resolver a pod can
  # use, and the gateway itself.
  #
  # A function rather than a module fragment. The parked lab's `aspects/` were
  # modules imported into a cluster, which merged; a cluster is an attrset of
  # instantiated floes now, so an aspect is a function returning one and `//`
  # composes them. `examples/labs/tests/secret-sharing.nix` does the same.
  platform = clusterName: {
    cluster = floes.k3d-cluster {
      name = clusterName;
      instanceName = instanceOf clusterName;

      # Two clusters on one docker network, so their pod and service ranges
      # have to be told apart. An address plan is a decision written down
      # (RFC 0005 §5), not something derived from the cluster's name — a
      # rename would silently move a running cluster's subnet.
      podSubnet = if clusterName == "core" then "10.244.0.0/16" else "10.245.0.0/16";
      serviceSubnet = if clusterName == "core" then "10.96.0.0/12" else "10.112.0.0/12";
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    # One root for the whole lab, minted on the host by `cert-generate` and
    # seeded into every cluster by `create-cluster`. Both clusters sign from
    # it, which is what lets one HAProxy terminate for both with one
    # certificate.
    cert-manager = floes.cert-manager {
      chart = "${cataCharts.cert-manager.chart}";
      rootFromLab = true;
    };

    # So a pod resolves `*.${zone}` too. Its resolver is the cluster's
    # CoreDNS, which has never heard of the lab.
    lab-dns = floes.lab-dns {
      inherit (config.lab.dns) zone server port;
    };

    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = zone;
      tlsEnable = true;
    };

    # Both clusters mint credentials rather than letting a chart write them
    # into the rendered manifests, so both need a generator.
    external-secrets = floes.external-secrets {
      chart = "${cataCharts.external-secrets.chart}";
      crds = "${cataCharts.external-secrets.crds}";
    };
  };
in
{
  lab.name = lib.mkDefault "homelab";
  lab.dns.zone = lib.mkDefault "homelab.test";

  # All three host services. The resolver answers for the zone, the ingress
  # routes by Host header to whichever cluster declared the route, and the
  # registry caches what two clusters would otherwise pull twice.
  lab.dns.enable = true;
  lab.proxy.enable = true;
  lab.registry.enable = true;

  lab.clusters.core.floes = platform "core" // {
    # ---- identity -------------------------------------------------------
    #
    # kaniop runs the CRDs; kanidm is the issuer. Its clients are rendered by
    # whoever needs one — there is no list of them here and kanidm does not
    # know who its consumers are.
    kaniop = floes.kaniop { chart = "${cataCharts.kaniop.chart}"; };
    kanidm = floes.kanidm { domain = "idm.${zone}"; };

    # ---- source control and registry ------------------------------------
    #
    # `oidc = true` on each is the whole of the wiring. The floe resolves
    # `OIDC_PROVIDER`, renders its own client into its own namespace, and
    # reads back the credential kanidm's operator writes.
    forgejo = floes.forgejo {
      chart = "${cataCharts.forgejo.chart}";
      oidc = true;
    };

    harbor = floes.harbor {
      chart = "${cataCharts.harbor.chart}";
      oidc = true;
    };

    # Restarts what reads a Secret or ConfigMap that changed underneath it —
    # which on this cluster is every OIDC consumer above.
    reloader = floes.reloader { chart = "${cataCharts.reloader.chart}"; };

    # ---- backups --------------------------------------------------------
    #
    # velero takes its endpoint off `OBJECT_STORE` rather than from a hostname
    # written twice, so the two cannot drift.
    seaweedfs = floes.seaweedfs { chart = "${cataCharts.seaweedfs.chart}"; };
    velero = floes.velero {
      chart = "${cataCharts.velero.chart}";
      crds = "${cataCharts.velero.crds}";
      schedules.daily = {
        schedule = "0 2 * * *";
        ttl = "168h";
      };
    };
  };

  lab.clusters.obs.floes = platform "obs" // {
    # All three backends, so all three of the collector's optional holes
    # resolve and Grafana gets three datasources.
    prometheus = floes.prometheus {
      chart = "${cataCharts.prometheus.chart}";
      crds = "${cataCharts.prometheus.crds}";
    };
    loki = floes.loki { chart = "${cataCharts.loki.chart}"; };
    tempo = floes.tempo { chart = "${cataCharts.tempo.chart}"; };

    otel-collector = floes.otel-collector { chart = "${cataCharts.otel-collector.chart}"; };

    # No `oidc`. The issuer is on `core`, and the hole resolves within a
    # cluster — see the header.
    grafana = floes.grafana { chart = "${cataCharts.grafana.chart}"; };
  };
}
