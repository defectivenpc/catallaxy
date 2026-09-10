# Prose under floes/ and docs/ that names something removed from the tree.
#
# Exempt: docs/rfcs/ and docs/prior-implementations.md (dated records),
# docs/floes/ (generated), and the pages in `namesTheOld`.
{ lib, pkgs }:

let
  # dead :: { Pattern -> Why }
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

  # namesTheOld :: { Path -> Why }, pages whose subject is the renaming.
  namesTheOld = {
    "docs/book/src/reference/glossary.md" = "its last table is the old-name index";
    "docs/book/src/reference/floe-api.md" = "says why `requiresMany` was replaced";
    "docs/book/src/reference/helpers.md" = "maps every deleted helper to its replacement";
  };

  prose = pkgs.runCommand "floe-headers-prose" { } ''
    mkdir -p $out
    cp -r ${../../floes} $out/floes
    cp -r ${../../docs} $out/docs
    chmod -R u+w $out
    rm -rf $out/docs/rfcs $out/docs/floes $out/docs/prior-implementations.md
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: "rm -f $out/${path}") namesTheOld)}
  '';
in
{
  floe-headers = pkgs.runCommand "floe-headers-tests" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
    status=0
    cd ${prose}

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
      echo "Prose names something not in the tree. Paths are repo-relative." >&2
      echo "History belongs in CHANGELOG.md." >&2
      exit 1
    fi
    echo "scanned $(find . -type f | wc -l) files under floes/ and docs/" > $out
  '';
}
