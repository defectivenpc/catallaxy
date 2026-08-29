# The cluster-scope floes this repo ships, as a value rather than an import
# list.
#
# A set keyed by floe name is what makes the registry overridable: a consumer
# can `removeAttrs` one, substitute a path for another, or add their own,
# and the quality gates can name floes without reading the directory back off
# disk. An `imports` list gives you none of that.
#
# Membership is still explicit. Adding a floe means adding a line here, which
# is the same cost as before and keeps `nix flake check` able to say which
# floes it checked.
{
  argocd = ./argocd;
  cert-manager = ./cert-manager;
  cnpg = ./cnpg;
  cilium = ./cilium;
  cluster-api = ./cluster-api;
  crossplane = ./crossplane;
  custom = ./custom;
  delivery = ./delivery;
  external-dns = ./external-dns;
  external-secrets = ./external-secrets;
  forgejo = ./forgejo;
  gateway = ./gateway;
  grafana = ./grafana;
  harbor = ./harbor;
  kanidm = ./kanidm;
  kaniop = ./kaniop;
  loki = ./loki;
  netbird = ./netbird;
  openbao = ./openbao;
  openebs = ./openebs;
  otel-collector = ./otel-collector;
  prometheus = ./prometheus;
  redis-operator = ./redis-operator;
  reloader = ./reloader;
  seaweedfs = ./seaweedfs;
  tempo = ./tempo;
  trust-manager = ./trust-manager;
  velero = ./velero;
  zot = ./zot;
}
