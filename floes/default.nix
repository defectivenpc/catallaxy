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
    cert-manager = ./cluster/cert-manager;
    cnpg = ./cluster/cnpg;
    custom = ./cluster/custom;
    delivery = ./cluster/delivery;
    external-dns = ./cluster/external-dns;
    external-secrets = ./cluster/external-secrets;
    gateway = ./cluster/gateway;
    gateway-api-crds = ./cluster/gateway-api-crds;
    kaniop = ./cluster/kaniop;
    lab-dns = ./cluster/lab-dns;
    loki = ./cluster/loki;
    openebs = ./cluster/openebs;
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

  provisioners = {
    k3d-cluster = ./provisioners/k3d-cluster.nix;
  };
}
