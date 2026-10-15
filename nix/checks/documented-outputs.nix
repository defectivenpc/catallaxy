/*
  Every `legacyPackages.<system>.<name>` and `packages.<system>.<name>` a
  document names resolves — either against this flake, or against the consumer
  contract it is describing.

  The book is where somebody looks up what to build, so a path that no longer
  resolves is worse than an undocumented one: it reads as a thing they got
  wrong. `k8sTypegenConfig` sat in the reference table long after both the
  output and the `cata generate` that consumed it were gone, as did
  `packages.option-docs` — which is `legacyPackages.optionDocs`. Nothing said
  so, because an output vanishing breaks no evaluation.

  `consumerOutputs` is the second half, and it is what makes the check honest
  rather than merely strict. `labs` and `labPackages` are paths the reader's
  own flake exposes, which is why the book names them and this flake does not:
  the example corpus moved to `examples/flake.nix`. Each is listed with a
  reason, and one this flake starts exposing fails as a stale entry, so the
  list cannot rot in either direction.

  Only the qualified forms, because `.#foo` cannot be told apart from a lab
  name or a shell alias. A "Common mistakes" table — a list of paths that
  deliberately do not resolve — is the one place a wrong path is the point, so
  the scan stops at that heading.

  History documents are exempt by fileset: `CHANGELOG.md` and `docs/adr/` are
  not in it, because they record what was true when written. So is
  `templates/`, which is a consumer flake in its own right.
*/
{
  lib,
  pkgs,
  legacyPackages,
  flakePackages,
  consumerOutputs,
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

  ours = {
    legacyPackages = lib.attrNames legacyPackages;
    packages = lib.attrNames flakePackages;
  };

  consumer = {
    legacyPackages = lib.attrNames consumerOutputs;
    packages = [ ];
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
        ours = builtins.toJSON ours;
        consumer = builtins.toJSON consumer;
        why = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (n: reason: "  ${n} — ${reason}") consumerOutputs
        );
        passAsFile = [
          "ours"
          "consumer"
          "why"
        ];
      }
      ''
        cd ${prose}

        status=0

        for kind in legacyPackages packages; do
          jq -r --arg k "$kind" '.[$k][]' "$oursPath" | sort -u > "$TMPDIR/ours"
          jq -r --arg k "$kind" '.[$k][]' "$consumerPath" | sort -u > "$TMPDIR/consumer"
          sort -u "$TMPDIR/ours" "$TMPDIR/consumer" > "$TMPDIR/allowed"

          find . -type f -name '*.md' | while read -r f; do
            sed '/^## Common mistakes/q' "$f" \
              | grep -noE "$kind\.[-A-Za-z0-9_<>.{}$]+\.[a-zA-Z][A-Za-z0-9-]*" \
              | sed -E "s|^([0-9]+):$kind\..*\.([a-zA-Z][A-Za-z0-9-]*)\$|\2 ''${f#./}:\1|" \
              || true
          done | sort -u > "$TMPDIR/named"

          cut -d' ' -f1 < "$TMPDIR/named" | sort -u > "$TMPDIR/names"

          for n in $(comm -23 "$TMPDIR/names" "$TMPDIR/allowed"); do
            echo "$kind.<system>.$n is documented, and nothing exposes it:" >&2
            grep "^$n " "$TMPDIR/named" | sed 's/^[^ ]* /    /' >&2
            status=1
          done

          for n in $(comm -12 "$TMPDIR/ours" "$TMPDIR/consumer"); do
            echo "$kind.<system>.$n is listed as the consumer's and this flake exposes it:" >&2
            echo "    drop the entry from consumerOutputs in nix/checks/default.nix" >&2
            status=1
          done
        done

        if [ "$status" != 0 ]; then
          echo "" >&2
          echo "Either expose it, correct the document, or — if the document is" >&2
          echo "describing the reader's own flake rather than this one — add it to" >&2
          echo "consumerOutputs in nix/checks/default.nix with a reason. Those are:" >&2
          cat "$whyPath" >&2
          echo "" >&2
          echo "  nix eval .#legacyPackages.<system> --apply builtins.attrNames" >&2
          echo "  nix eval ./examples#legacyPackages.<system> --apply builtins.attrNames" >&2
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
