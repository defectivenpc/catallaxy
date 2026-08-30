# secret-store, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "secret-store";
    inputs = {
      labStore = "runtime";
      server = "https://vault.test";
    };
  };

  store = r.bundles.store.resources.store;
in
lib.runTests {
  # Derived from the lab store, not configured, so the lab wiring that
  # references it and this floe cannot name different things.
  testTheObjectNameIsDerivedFromTheLabStore = {
    expr = store.metadata.name;
    expected = "catallaxy-runtime";
  };

  testTheProvideNamesTheSameObject = {
    expr = r.provides.store.storeName;
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

  testWritableByDefault = {
    expr = r.provides.store.writable;
    expected = true;
  };
}
