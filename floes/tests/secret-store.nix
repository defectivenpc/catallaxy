# secret-store, alone.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe {
    name = "secret-store";
    inputs.server = "https://vault.test";
  };

  store = r.bundles.store.resources.store;
in
lib.runTests {
  # Derived from the lab store this resolved, not configured — so there is no
  # second place the store's name is written. It was a `labStore = "<name>"`
  # input naming an attribute under `lab.secrets.stores` with nothing checking
  # it.
  testTheObjectNameIsDerivedFromTheLabStore = {
    expr = store.metadata.name;
    expected = "catallaxy-stub-labStore";
  };

  testTheProvideNamesTheSameObject = {
    expr = r.provides.secretStore.storeName;
    expected = store.metadata.name;
  };

  # Cluster-scoped: a value minted in one namespace is usually read in
  # another, and a `SecretStore` is only visible to the namespace holding it.
  testItIsClusterScoped = {
    expr = store.kind;
    expected = "ClusterSecretStore";
  };

  # The token is an ordinary Secret this floe does not create. Naming it is
  # what keeps the cluster's coherence check honest about the dependency.
  testItDeclaresTheTokenItDoesNotCreate = {
    expr = r.bundles.store.needsSecrets;
    expected = [ "external-secrets/vault-token" ];
  };

  # A store elsewhere is signed by a public CA and must keep using the pod's
  # own roots, so this is off unless asked for.
  testNoCaProviderByDefault = {
    expr = store.spec.provider.vault ? caProvider;
    expected = false;
  };

  # Whether a cluster may push into it comes off the store, which derives it
  # from its backend. It was an input beside the `labStore` string, so a lab
  # could call a vault-backed store read-only or a sops-backed one writable
  # and nothing would notice until a PushSecret never reconciled.
  #
  # The stub answers the authored case, which is what every floe reading a
  # projected value is in. `floes/tests/lab-secret-store.nix` covers both
  # sides of the derivation.
  testWritableComesFromTheStore = {
    expr = r.provides.secretStore.writable;
    expected = false;
  };
}
