# The readiness tokens a cluster's lifecycle publishes.
#
# One spelling per token, because a producer and a consumer have to agree on
# the exact string and an `optional:` anchor that matches nothing fails
# silently. `checks.plan-tokens` refuses a token literal written anywhere else.
{ lib }:

let
  clusterTokens = name: {
    created = "cluster/${name}/created";
    deployed = "cluster/${name}/deployed";
    kubeconfigSynced = "cluster/${name}/kubeconfig-synced";
    cleanup = "cluster/${name}/cleanup";
    cloudReleased = "cluster/${name}/cloud-released";
    managedResourceAdopted = "cluster/${name}/mr-adopted";
    managedResourceReconciled = "cluster/${name}/mr-reconciled";
    managedResourceDeleted = "cluster/${name}/mr-deleted";
    gone = "cluster/${name}/gone";
    destroyed = "cluster/${name}/destroyed";
  };

  stackTokens = name: {
    planned = "stack/${name}/planned";
    applied = "stack/${name}/applied";
    destroyed = "stack/${name}/destroyed";
  };
in
{
  cluster = clusterTokens;
  stack = stackTokens;

  lab = {
    network = "lab/network";
    ingressCa = "lab/ingress-ca";
    hostDns = "host/dns";
    hostDnsRemoved = "host/dns-removed";
    registryConfig = "lab/registry-config";
    secrets = "lab/secrets";
    services = "lab/services";
    warmCache = "lab/warm-cache";
    # Argo applied, before it can apply anything else.
    cdBootstrapped = "lab/cd-bootstrapped";
    gitReady = "lab/git-ready";
    manifestsPushed = "lab/manifests-pushed";
    # The cluster is Argo's now; `cata` has stopped applying.
    cdHandedOver = "lab/cd-handed-over";
    reachable = "host/lab-reachable";
    cleanup = "lab/cleanup";
    servicesRemoved = "lab/services-removed";
    networkRemoved = "lab/network-removed";
  };
}
