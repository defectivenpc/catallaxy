# Where a shared secret lives in a runtime store, and what the store is called
# in a cluster.
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

  storeResourceName = store: "catallaxy-${store}";
}
