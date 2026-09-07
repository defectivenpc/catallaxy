# The readiness tokens a cluster's lifecycle publishes.
{ lib }:

let
  clusterTokens = name: {
    created = "cluster/${name}/created";
    reachable = "cluster/${name}/reachable";
    bootstrapDeployed = "cluster/${name}/bootstrap-deployed";
    provisionerDone = "cluster/${name}/provisioner-done";
    kubeconfigSynced = "cluster/${name}/kubeconfig-synced";
    pivoted = "cluster/${name}/pivoted";
    deployed = "cluster/${name}/deployed";
    argocdInstalled = "cluster/${name}/argocd-installed";
    forgejoBootstrapped = "cluster/${name}/forgejo-bootstrapped";
    gitReady = "cluster/${name}/git-ready";
    gitopsStarted = "cluster/${name}/gitops-started";
    cleanup = "cluster/${name}/cleanup";
    cloudReleased = "cluster/${name}/cloud-released";
    managedResourceAdopted = "cluster/${name}/mr-adopted";
    managedResourceDeleted = "cluster/${name}/mr-deleted";
    gone = "cluster/${name}/gone";
    destroyed = "cluster/${name}/destroyed";
  };
  stackTokens = name: {
    applied = "stack/${name}/applied";
    destroyed = "stack/${name}/destroyed";
  };
in
{
  cluster = clusterTokens;
  stack = stackTokens;

  lab = {
    preflightOk = "lab/preflight-ok";
    network = "lab/network";
    hostNetwork = "lab/host-network";
    ingressCa = "lab/ingress-ca";
    hostTrust = "host/trust";
    hostTrustOs = "host/trust/os";
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

  needs = token: "provides:${token}";
  wants = token: "optional:provides:${token}";
  wantsAll = tokens: map (token: "optional:provides:${token}") tokens;
  wantsKind = kind: "optional:kind:${kind}";
}
