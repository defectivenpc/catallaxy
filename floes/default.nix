# The floes catallaxy ships :: { Group -> { FloeName -> Path } }
#
# An attrset so a consumer can `removeAttrs` one or substitute their own.
# `lib/lab.nix` flattens the groups; they are disk layout, not a namespace.
{
  cluster = {
    argocd = ./cluster/argocd;
    cert-manager = ./cluster/cert-manager;
    cilium = ./cluster/cilium;
    cnpg = ./cluster/cnpg;
    crossplane = ./cluster/crossplane;
    crossplane-provider-nop = ./cluster/crossplane-provider-nop;
    custom = ./cluster/custom;
    doks = ./cluster/doks;
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
    nop-resource = ./cluster/nop-resource;
    openbao = ./cluster/openbao;
    openebs = ./cluster/openebs;
    otel-collector = ./cluster/otel-collector;
    podinfo = ./cluster/podinfo;
    provisioned = ./cluster/provisioned;
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
    external-cluster = ./provisioners/external-cluster.nix;
    k3d-cluster = ./provisioners/k3d-cluster.nix;
    talos-cluster = ./provisioners/talos-cluster.nix;
  };
}
