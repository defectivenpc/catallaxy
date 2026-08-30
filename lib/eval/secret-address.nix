# Where a shared secret lives in a runtime store, and what the store is called
# in a cluster.
#
# Both are pure functions of identity, and that is the whole design. The
# publisher derives the address from its own name; every subscriber derives the
# same string from the cluster it names. Nothing is negotiated, so nothing can
# cycle, and a publisher never learns who reads it.
#
# One file because these are the two strings a producer and a consumer must
# agree on without talking, and two spellings that could drift is exactly the
# failure that leaves an ExternalSecret waiting forever on a key nothing wrote.
{ lib }:

{
  # remoteKey :: { lab; cluster; namespace; secret; } -> str
  #
  # Namespaced by the producing cluster, not the consuming one: a value means
  # "the credential cluster X minted", and two clusters publishing the same
  # name are two different values.
  remoteKey =
    {
      lab,
      cluster,
      namespace,
      secret,
    }:
    "${lab}/${cluster}/${namespace}/${secret}";

  # What the `ClusterSecretStore` for a lab store is called in-cluster.
  #
  # Derived rather than configured so the floe that renders the store and the
  # lab wiring that references it cannot disagree. Prefixed because the object
  # is cluster-scoped and shares a namespace with whatever else is installed.
  storeResourceName = store: "catallaxy-${store}";
}
