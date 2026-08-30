# Pod-template annotations a workload carries so a controller acts on it.
#
# This is where `reloader.mkPatches` went. It used to be an *export* — a
# function on the floe's signature — and RFC 0001 forbids functions in a
# signature: they cannot be checked at eval, do not serialize into the IR, and
# defeat `checkFloe`. It was the only such export in all 29 floes.
#
# What crosses the boundary is the two annotation keys, which are strings and
# travel fine on `CONFIG_RELOAD`. Building an annotation set out of them is a
# pure function of data both sides already have, so it lives here, where a
# function is unremarkable.
{ lib }:

{
  # reloadAnnotations :: CONFIG_RELOAD -> { secrets ? [str]; configMaps ? [str]; } -> attrs
  #
  # Reloader watches a comma-separated list of names in the workload's own
  # namespace. An empty list means the key is absent rather than empty: the
  # controller treats `""` as "reload on any change", which is not what a
  # caller listing nothing meant.
  reloadAnnotations =
    reload:
    {
      secrets ? [ ],
      configMaps ? [ ],
    }:
    lib.optionalAttrs (secrets != [ ]) {
      ${reload.secretAnnotation} = lib.concatStringsSep "," secrets;
    }
    // lib.optionalAttrs (configMaps != [ ]) {
      ${reload.configMapAnnotation} = lib.concatStringsSep "," configMaps;
    };
}
