# Two clusters sharing a secret through a runtime store.
#
# The chain, end to end, is the point:
#
#   an authored store holds the credential for the runtime store
#     -> projected into each cluster as the token its ClusterSecretStore uses
#       -> `core` mints a CA and publishes it
#         -> `obs` subscribes and materialises it under its own name
#
# Neither cluster reads the other's configuration. `core` derives the address
# from its own identity; `obs` derives the same string from the cluster it
# names. Nothing is negotiated, so nothing can cycle and `core` never learns
# who reads it.
#
# It renders and is checked like any lab and never enters the e2e set: it
# needs a vault, which a fixture has no business standing up. What it pins is
# that the two sides agree, which is exactly the half that has no runtime
# symptom short of an ExternalSecret waiting forever.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:

let
  # One store, reachable from both clusters. Deliberately not an in-cluster
  # address: that resolves only inside the cluster running it, and the lab
  # refuses one used by more than a single cluster.
  vaultServer = "https://vault.${config.lab.dns.zone}";

  # Every cluster needs the same three: the controller, a store pointed at the
  # shared backend, and the token that store authenticates with.
  sharedFloes = clusterName: {
    cluster = floes.k3d-cluster {
      name = clusterName;
      instanceName = "secret-sharing-${clusterName}";

      # Distinct ranges, because the two clusters share a docker network. Both
      # took the defaults until `lab-cluster-ranges` was written and said so —
      # invisible here, since a fixture renders and never runs, and the same
      # mistake in a lab that does run is two clusters handing out the same
      # pod addresses.
      podSubnet = if clusterName == "core" then "10.244.0.0/16" else "10.245.0.0/16";
      serviceSubnet = if clusterName == "core" then "10.96.0.0/12" else "10.112.0.0/12";
    };

    external-secrets = floes.external-secrets {
      chart = "${cataCharts.external-secrets.chart}";
      crds = "${cataCharts.external-secrets.crds}";
    };

    store = floes.secret-store {
      labStore = "runtime";
      server = vaultServer;
    };
  };

  # The token reaches each cluster the way the store floe's docstring says it
  # does: authored in sops, projected in. It is not a value the lab mints.
  tokenProjection = {
    vault-token = {
      source = "vault-credential";
      namespace = "external-secrets";
      keys.token.from = "token";
    };
  };
in
{
  lab.name = "secret-sharing";
  lab.dns.zone = "secret-sharing.test";
  lab.network.subnet = "172.31.0.0/16";

  lab.secrets.stores = {
    # Authored: you write the value, and it is projected into every cluster
    # that needs it. A cluster cannot write back.
    authored.backend = "sops";

    # Runtime: a cluster may write into it, which is what makes a value one
    # cluster mints reachable from another.
    runtime = {
      backend = "vault";
      vault.server = vaultServer;
    };
  };

  lab.secrets.managed.vault-credential = {
    store = "authored";
    keys.token.generator = "hex";
    keys.token.length = 32;
  };

  # ---- the producer ------------------------------------------------------

  lab.clusters.core = {
    floes = sharedFloes "core" // {
      # It mints its own root, so the CA Secret genuinely exists here — which
      # is what makes this a real thing to share rather than a fixture.
      cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    };

    secrets.project = tokenProjection;

    secrets.publish.lab-ca-ca-secret = {
      namespace = "cert-manager";
    };
  };

  # ---- the consumer ------------------------------------------------------

  lab.clusters.obs = {
    floes = sharedFloes "obs";

    secrets.project = tokenProjection;

    secrets.subscribe.lab-ca-ca-secret = {
      from = "core";
      namespace = "default";

      # Landed under a name that says what it is here, rather than what it was
      # called where it was minted.
      secret = "core-lab-ca";

      # What reads a Secret often finds it by label rather than by name.
      labels."catallaxy.io/trust" = "lab-ca";
    };
  };
}
