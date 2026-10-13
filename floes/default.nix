# The floes catallaxy ships :: { Group -> { FloeName -> Path } }
#
# An attrset so a consumer can `removeAttrs` one or substitute their own.
# `lib/lab.nix` flattens the groups; they are disk layout, not a namespace.
#
# A group says *where the unit sits*, which is the only question that cannot be
# answered by reading the floe's inputs:
#
#   provisioners  is the claim — it makes the cluster the others install into
#   components    inside a cluster
#   clusters      an assembly of components, placed as one thing
#   delivery      how a cluster's content reaches it
#   lab           at lab scope: installs nothing, answers a signature every
#                 cluster can resolve
#
# Which is also why `lab` is a group of one and that is not a smell. The
# alternative is `lab/zone.nix` filed under `components/` while being the one
# thing that is not in a cluster.
{
  components = {
    argocd = ./components/argocd;
    cert-manager = ./components/cert-manager;
    cilium = ./components/cilium;
    cnpg = ./components/cnpg;
    crossplane = ./components/crossplane;
    crossplane-provider-nop = ./components/crossplane-provider-nop;
    custom = ./components/custom;
    doks = ./components/doks;
    external-dns = ./components/external-dns;
    external-secrets = ./components/external-secrets;
    grafana = ./components/grafana;
    forgejo = ./components/forgejo;
    gateway = ./components/gateway;
    gateway-api-crds = ./components/gateway-api-crds;
    harbor = ./components/harbor;
    kanidm = ./components/kanidm;
    kaniop = ./components/kaniop;
    coredns-zone = ./components/coredns-zone;
    loki = ./components/loki;
    netbird = ./components/netbird;
    netbird-operator = ./components/netbird-operator;
    nop-resource = ./components/nop-resource;
    openbao = ./components/openbao;
    openebs = ./components/openebs;
    otel-collector = ./components/otel-collector;
    podinfo = ./components/podinfo;
    provisioned = ./components/provisioned;
    prometheus = ./components/prometheus;
    redis-operator = ./components/redis-operator;
    reloader = ./components/reloader;
    seaweedfs = ./components/seaweedfs;
    secret-projection = ./components/secret-projection;
    secret-publication = ./components/secret-publication;
    secret-store = ./components/secret-store;
    secret-subscription = ./components/secret-subscription;
    tempo = ./components/tempo;
    trust-manager = ./components/trust-manager;
    velero = ./components/velero;
    zot = ./components/zot;
  };

  # Floes whose units are components: an assembly with an interface, which a
  # lab places as one thing. Its claim and its zone are left open.
  clusters = {
    standard-cluster = ./clusters/standard-cluster.nix;
  };

  # How a cluster's content reaches it. A delivery floe answers
  # `DELIVERY_POLICY` and installs nothing of its own, or installs the tool
  # that takes over — `argocd` is a component because it does.
  delivery = {
    kapp = ./delivery/kapp.nix;
  };

  # Floes that live at lab scope rather than in a cluster: they install
  # nothing and answer a signature every cluster can resolve.
  lab = {
    lab-network = ./lab/network.nix;
    lab-ca = ./lab/ca.nix;
    lab-zone = ./lab/zone.nix;
    lab-egress = ./lab/egress.nix;
    lab-registry = ./lab/registry.nix;
    lab-dns = ./lab/dns.nix;
    lab-proxy = ./lab/proxy.nix;
    lab-services = ./lab/services.nix;
    lab-steps = ./lab/steps.nix;
    lab-secret-store = ./lab/secret-store.nix;
    lab-authored-secret = ./lab/authored-secret.nix;
    lab-secrets = ./lab/secrets.nix;
    lab-delivery = ./lab/delivery.nix;
  };

  provisioners = {
    external-cluster = ./provisioners/external-cluster.nix;
    k3d-cluster = ./provisioners/k3d-cluster.nix;
    provisions-cluster = ./provisioners/provisions-cluster.nix;
    talos-cluster = ./provisioners/talos-cluster.nix;
  };
}
