# The floes catallaxy ships, as name -> path.
#
# An attribute set rather than an import list, so a consumer can `removeAttrs`
# one or substitute their own. Membership is explicit: adding a floe means
# adding a line here, which is what keeps a check able to say which floes it
# checked.
#
# `lib/lab.nix` flattens the two groups — the split is how the set is
# organised on disk, not a namespace a lab has to spell.
{
  cluster = {
    argocd = ./cluster/argocd;
    cert-manager = ./cluster/cert-manager;
    cilium = ./cluster/cilium;
    cnpg = ./cluster/cnpg;
    custom = ./cluster/custom;
    external-dns = ./cluster/external-dns;
    external-secrets = ./cluster/external-secrets;
    grafana = ./cluster/grafana;
    forgejo = ./cluster/forgejo;
    gateway = ./cluster/gateway;
    gateway-api-crds = ./cluster/gateway-api-crds;
    harbor = ./cluster/harbor;
    kanidm = ./cluster/kanidm;
    kaniop = ./cluster/kaniop;
    lab-dns = ./cluster/lab-dns;
    loki = ./cluster/loki;
    netbird = ./cluster/netbird;
    netbird-operator = ./cluster/netbird-operator;
    openbao = ./cluster/openbao;
    openebs = ./cluster/openebs;
    otel-collector = ./cluster/otel-collector;
    podinfo = ./cluster/podinfo;
    prometheus = ./cluster/prometheus;
    redis-operator = ./cluster/redis-operator;
    reloader = ./cluster/reloader;
    seaweedfs = ./cluster/seaweedfs;
    secret-store = ./cluster/secret-store;
    tempo = ./cluster/tempo;
    trust-manager = ./cluster/trust-manager;
    velero = ./cluster/velero;
    zot = ./cluster/zot;
  };

  # Floes that live at lab scope rather than in a cluster: they install
  # nothing and answer a signature every cluster can resolve.
  lab = {
    lab-zone = ./lab/zone.nix;
  };

  provisioners = {
    k3d-cluster = ./provisioners/k3d-cluster.nix;
  };
}
