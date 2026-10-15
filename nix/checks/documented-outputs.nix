/*
  Every `legacyPackages.<system>.<name>` and `packages.<system>.<name>` a
  document names is an output the flake has.

  The book is where somebody looks up what to build, so a path that no longer
  resolves is worse than an undocumented one: it reads as a thing they got
  wrong. `k8sTypegenConfig` sat in the reference table long after both the
  output and the `cata generate` that consumed it were gone, as did
  `packages.option-docs` — which is `legacyPackages.optionDocs`. Nothing said
  so, because an output vanishing breaks no evaluation.

  Only the qualified forms, because `.#foo` cannot be told apart from a lab
  name or a shell alias, and because this file's own "Common mistakes" table
  is a list of paths that deliberately do not resolve. That table is the one
  place a wrong path is the point, so the scan stops at its heading.

  History documents are exempt by fileset: `CHANGELOG.md` and `docs/adr/` are
  not in it, because they record what was true when written. So is
  `templates/`, whose `legacyPackages.${system}` is the consumer's own flake
  rather than this one.
*/
{
  lib,
  pkgs,
  legacyPackages,
  flakePackages,
}:

let
  prose = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../docs/book/src
      ../../README.md
      ../../CONTEXT.md
    ];
  };

  surface = {
    legacyPackages = lib.attrNames legacyPackages;
    packages = lib.attrNames flakePackages;
  };
in
{
  documented-outputs =
    pkgs.runCommand "documented-outputs"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.gnused
          pkgs.coreutils
          pkgs.findutils
          pkgs.jq
        ];
        surface = builtins.toJSON surface;
        passAsFile = [ "surface" ];
      }
      ''
        cd ${prose}

        status=0

        for kind in legacyPackages packages; do
          jq -r --arg k "$kind" '.[$k][]' "$surfacePath" | sort -u > "$TMPDIR/have"

          find . -type f -name '*.md' | while read -r f; do
            sed '/^## Common mistakes/q' "$f" \
              | grep -noE "$kind\.[-A-Za-z0-9_<>.{}$]+\.[a-zA-Z][A-Za-z0-9-]*" \
              | sed -E "s|^([0-9]+):$kind\..*\.([a-zA-Z][A-Za-z0-9-]*)\$|\2 ''${f#./}:\1|" \
              || true
          done | sort -u > "$TMPDIR/named"

          cut -d' ' -f1 < "$TMPDIR/named" | sort -u > "$TMPDIR/names"

          for n in $(comm -23 "$TMPDIR/names" "$TMPDIR/have"); do
            echo "$kind.<system>.$n is documented, and the flake has no such output:" >&2
            grep "^$n " "$TMPDIR/named" | sed 's/^[^ ]* /    /' >&2
            status=1
          done
        done

        if [ "$status" != 0 ]; then
          echo "" >&2
          echo "Either expose it, or correct the document to name what replaced it." >&2
          echo "  nix eval .#legacyPackages.<system> --apply builtins.attrNames" >&2
          echo "" >&2
          echo "If the path above is one of a table of paths that are meant not to" >&2
          echo "resolve, it is below a heading this check no longer recognises: the" >&2
          echo "scan stops at '## Common mistakes', and that string is in" >&2
          echo "nix/checks/documented-outputs.nix." >&2
          exit 1
        fi

        echo "every documented output path resolves" > $out
      '';
}
