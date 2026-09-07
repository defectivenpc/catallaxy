# A lab with a cluster in a cloud.
#
# `home` is a k3d cluster on the operator's machine. `workload` is a DOKS
# cluster: declared as a resource in `home` (RFC 0003 — something has to make
# the first cluster, and before one exists there is no reconciler), and named
# as an ordinary `lab.clusters` entry so the lab installs into it once it is
# there.
#
# The point is how little is special. Compared with `minimal.local`:
#
#   - one instantiation is `floes.external-cluster` instead of
#     `floes.k3d-cluster`, and no member of `workload` changes (RFC 0005 §8.2)
#   - `workload` answers `edge.mode = "self"`, so the lab's proxy renders no
#     backend for it and `cata lab verify` does not resolve its hostnames to
#     loopback (RFC 0005 §6.4)
#   - `home` carries a `doks` floe whose delivery is `resources` rather than
#     bundles, and the plan gains `infra-{plan,apply}` before any cluster
#
# It renders, lints, plans and digests with **no credential on this machine**:
# `cata lab plan` reads only the lab document, and the only step that reaches
# an account is `infra-apply`, which is gated behind `--infra` and is
# `dryRunSafe = false`. That is what makes a cloud lab checkable in
# `nix flake check` at all.
#
# It is a fixture and never enters the e2e set. Standing it up costs money.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  ...
}:

let
  members = {
    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    gateway = floes.gateway { chart = "${cataCharts.traefik.chart}"; };
  };
in
{
  lab.name = "cloud";
  lab.dns.zone = "cloud.test";
  lab.network.subnet = "172.43.0.0/16";
  lab.egress.port = 3138;
  lab.dns.hostPort = 5373;

  # On, and it fronts `home` only. A lab that turned it off would pass the
  # edge checks by having nothing to route rather than by routing the right
  # subset.
  lab.proxy.enable = true;
  lab.proxy.httpPort = 8092;
  lab.proxy.httpsPort = 8451;

  # Where the cluster's kubeconfig lands when the apply produces it. `env`
  # rather than sops so the fixture needs no key to evaluate; a real lab would
  # use a runtime store its clusters can read.
  lab.secrets.stores.cloud.backend = "env";

  lab.clusters.home.floes = members // {
    cluster = floes.k3d-cluster {
      name = "home";
      instanceName = "cloud-home";
    };

    # The other camp. Declared here because a resource has to be *somewhere*,
    # and the operator's own cluster is where a lab keeps the thing that
    # brings the cloud one into existence.
    doks = floes.doks {
      name = "cloud-workload";
      version = "1.31.1-do.4";
      nodeCount = 2;

      publishKubeconfigTo = {
        store = "cloud";
        key = "clusters/workload/kubeconfig";
      };
    };
  };

  lab.clusters.workload.floes = members // {
    cluster = floes.external-cluster {
      name = "workload";

      # A name catallaxy chooses. `doctl` would call this `do-nyc3-<name>`;
      # writing the fetched kubeconfig under a name the lab decides is what
      # keeps `KUBERNETES_CLUSTER.context` concrete for a cluster whose
      # endpoint is not (RFC 0005 §6.3).
      context = "cata-cloud-workload";
      madeBy = "opentofu, from the 'doks' floe on 'home'";

      # DOKS assigns these and the provider reports them read-only, so they
      # are declared here and the resource reads them back as outputs —
      # a decision that is *checked* rather than a value that is sampled.
      # Getting them wrong is a cluster whose members render network policies
      # against ranges it does not use.
      podSubnet = "10.244.0.0/16";
      serviceSubnet = "10.245.0.0/16";

      # DOKS runs a cloud controller, so a LoadBalancer Service gets an
      # address and the gateway is an ordinary LoadBalancer rather than the
      # NodePort a bare Talos cluster needs.
      assignsLoadBalancers = true;

      # The other end of the `doks` floe's publication above, and the same
      # address written once on each side. The lab derives a step from this
      # that writes the kubeconfig locally under `context` — without it the
      # lab is refused, because every step addressing this cluster would run
      # against a context nothing wrote.
      kubeconfigFrom = {
        store = "cloud";
        key = "clusters/workload/kubeconfig";
      };
    };

    podinfo = floes.podinfo { };
  };
}
