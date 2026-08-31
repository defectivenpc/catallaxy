# One cluster that reconciles itself.
#
# A fixture, not a runnable lab, and the reason is recorded rather than
# assumed: it gets as far as Argo CD being fully up and fails at
# `bootstrap-forgejo-repos`, which waits for a Job labelled
# `app.kubernetes.io/component=forgejo-bootstrap` that the forgejo floe does
# not render. Until it does, this renders and snapshots and does not run —
# the same standing as `every-floe`.
#
# The lab Round 4 exists for, and the first that hands delivery over: `cata`
# applies Argo CD and the git server, publishes the rendered tree into that
# server, and then stops applying. Argo takes it from there.
#
# Nothing here says any of that. `argocd` provides DELIVERY_POLICY with
# `strategy = "argocd"`, `forgejo` provides GIT_REPOSITORY, and
# `modules/lab/cd.nix` derives the four extra steps and their order from those
# two facts. A lab author picks floes.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:

let
  instanceOf = clusterName: "${lib.replaceStrings [ "." ] [ "-" ] config.lab.name}-${clusterName}";
in
{
  lab.name = "gitops.local";
  lab.dns.zone = "gitops.test";

  # Its own subnet and ports, so it stands up beside the minimal labs rather
  # than fighting them for the network.
  lab.network.subnet = "172.32.0.0/16";
  lab.proxy.httpPort = 8082;
  lab.proxy.httpsPort = 8445;
  lab.dns.hostPort = 5358;
  lab.registry.port = 5054;
  lab.egress.port = 3131;

  lab.registry.enable = true;

  # Argo clones over TLS from a certificate the lab mints, and Forgejo's own
  # routed URL has to be reachable for a human to look at it.
  lab.dns.enable = true;
  lab.proxy.enable = true;
  lab.verify.endpoints.enable = true;

  lab.clusters.app.floes = {
    cluster = floes.k3d-cluster {
      name = "app";
      instanceName = instanceOf "app";
    };

    # ---- the platform underneath ----------------------------------------

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };

    cert-manager = floes.cert-manager {
      chart = "${cataCharts.cert-manager.chart}";
      rootFromLab = true;
    };

    trust-manager = floes.trust-manager {
      chart = "${cataCharts.trust-manager.chart}";
    };

    lab-dns = floes.lab-dns {
      inherit (config.lab.dns) zone server port;
    };

    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = config.lab.dns.zone;
      tlsEnable = true;
    };

    # forgejo and argocd both mint credentials rather than letting their
    # charts write them into the rendered manifests, so both need a generator.
    external-secrets = floes.external-secrets {
      chart = "${cataCharts.external-secrets.chart}";
      crds = "${cataCharts.external-secrets.crds}";
    };

    # No openebs. k3s ships a `local-path` StorageClass and openebs installs
    # one under the same name with a different provisioner — which is an
    # immutable field, so the apply fails on every attempt and never
    # converges. A lab that wants openebs has to turn k3s's off, and
    # `k3d-cluster` has no input for that yet.
    #
    # Nothing here needs it: forgejo and argocd take PVCs, and k3s's
    # provisioner serves them.

    # ---- the two that make it gitops ------------------------------------

    forgejo = floes.forgejo { chart = "${cataCharts.forgejo.chart}"; };

    argocd = floes.argocd { chart = "${cataCharts.argocd.chart}"; };

    # Something for Argo to have applied, so the lab proves more than that
    # Argo started.
    podinfo = floes.podinfo { };
  };
}
