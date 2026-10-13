# What a lab's store is called in a cluster.
#
# There used to be a `remoteKey` here too — `<lab>/<cluster>/<ns>/<secret>` —
# derived on the producing side and again on the consuming side, with
# assertions checking the two derivations agreed. A publication names its key
# now and provides it, so there is one derivation and nothing to compare.
{ lib }:

{
  storeResourceName = store: "catallaxy-${store}";
}
