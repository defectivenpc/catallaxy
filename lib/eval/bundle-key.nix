{ }:

# How a bundle key becomes a directory name.
#
# A key is a path-shaped thing — `projection/harbor-admin` — and a directory
# name cannot hold the separator, so `/` becomes `__`.
#
# This is load-bearing rather than cosmetic: `dir-builder` *writes* the
# directory, and `manifest`, `fleet`, `argocd` and `sbom` all *name* it again
# to reference it. It was written out five times, so any one of them drifting
# would have pointed four consumers at a path the fifth never created — and
# nothing would have failed at eval, only at apply.

{
  sanitize = builtins.replaceStrings [ "/" ] [ "__" ];
}
