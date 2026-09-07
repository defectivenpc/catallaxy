# Floe prose that describes something no longer here.
#
# A narrow check, and honest about it: it cannot judge whether a comment is
# good, only whether it names a thing that has been removed. Every entry below
# is a real removal, and each was found in the tree — `otel-collector`
# explained its whole design in terms of `requiresMany` for as long as that
# primitive had been gone, and twenty headers opened with a line count against
# a floe nobody can read.
#
# The rule it enforces, which the good headers already follow
# (`floes/cluster/lab-dns/default.nix`, `floes/cluster/openebs/default.nix`):
# a header is for someone using the floe *today*. What it installs, why it
# exists, and the decision they would otherwise reverse-engineer from the
# body. History belongs in `CHANGELOG.md`, which is two thousand lines long
# and exists for exactly this.
{ lib, pkgs }:

let
  # `pattern -> why it is dead`. The message is the check's whole value: a
  # grep hit with no explanation sends the reader to git log.
  dead = {
    "requiresMany" = "replaced by `requiresOptional` in lib/floe-core/floe.nix";
    "lines against" = "a line count against a deleted tree, wrong within one commit";
    "parked floe" = "the parked tree was deleted; see CHANGELOG.md";
    "parked tree" = "the parked tree was deleted; see CHANGELOG.md";
    "internalHostnames" = "the gateway fan-in was inverted; consumers render their own routes";
    "bootstrapManifests" = "now an `autoDeployManifests` input on the provisioner floe";
    "cluster.prerequisites" = "replaced by exactly-one-provider resolution";
    "ROUTE_REQUEST" = "the routing inversion removed it; see sigs.nix API_GATEWAY";
    ".exports" = "floes provide signatures; there is no exports channel";
  };
in
{
  floe-headers = pkgs.runCommand "floe-headers-tests" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
    status=0
    cd ${../../floes}

    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (pattern: why: ''
        if hits=$(grep -rnF -- ${lib.escapeShellArg pattern} . 2>/dev/null); then
          echo "$hits" | sed 's/^/  /' >&2
          echo "    ^ mentions ${pattern}: ${why}" >&2
          echo "" >&2
          status=1
        fi
      '') dead
    )}

    if [ "$status" != 0 ]; then
      echo "A floe's comments describe something that is not in the tree." >&2
      echo "" >&2
      echo "A header is for someone using the floe today: what it installs," >&2
      echo "why it exists, and the decision they would otherwise work out by" >&2
      echo "reading the body. What the code used to be belongs in CHANGELOG.md." >&2
      exit 1
    fi
    touch $out
  '';
}
