{
  components = {
    argocd = ./components/argocd;
    cert-manager = ./components/cert-manager;
    cilium = ./components/cilium;
    cnpg = ./components/cnpg;
    crossplane = ./components/crossplane;
    crossplane-provider-nop = ./components/crossplane-provider-nop;
    custom = ./components/custom;
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

  clusters = {
    standard-cluster = ./clusters/standard-cluster.nix;
  };

  delivery = {
    kapp = ./delivery/kapp.nix;
  };

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
