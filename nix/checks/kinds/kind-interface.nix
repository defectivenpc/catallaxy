# What each output kind's shape says, pinned.
#
# The third of the three interface nets, beside `floe-interface-<name>` and
# `signature-interface-<name>`. A kind page is the schema `conformValue` holds
# a floe to, so it moving means what a floe may write changed — and until these
# pages existed, the only way to learn a bundle's shape was to read
# `component-schema.nix`.
{
  lib,
  pkgs,
  referencePages,
  docDir,
  catallaxy,
}:

let
  isKind = v: (v.__floeSig or false) && lib.hasPrefix "catallaxy." (v.name or "");
  kindSet = lib.filterAttrs (_: isKind) catallaxy.kinds;
in
lib.foldl' lib.mergeAttrs { } (
  lib.mapAttrsToList (attr: _: {
    "kind-interface-${attr}" =
      pkgs.runCommand "kind-interface-${attr}" { nativeBuildInputs = [ pkgs.diffutils ]; }
        ''
          if ! diff -u ${docDir}/${attr}.md ${referencePages}/kinds/${attr}.md; then
            echo "" >&2
            echo "The shape of 'catallaxy.${attr}' changed." >&2
            echo "" >&2
            echo "This is what a floe writing it is checked against, so the diff is" >&2
            echo "a change to what every floe writing this kind may say — or to" >&2
            echo "which floes those are." >&2
            echo "" >&2
            echo "If intended, refresh it and read the diff:" >&2
            echo "" >&2
            echo "  nix build .#referencePages   # then copy over docs/generated" >&2
            exit 1
          fi
          touch $out
        '';
  }) kindSet
  ++ [
    {
      kind-index = pkgs.runCommand "kind-index" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
        if ! diff -u ${docDir}/index.md ${referencePages}/kinds/index.md; then
          echo "" >&2
          echo "The output-kind index is stale — a kind was added or removed." >&2
          echo "  nix build .#referencePages   # then copy over docs/generated" >&2
          exit 1
        fi
        touch $out
      '';
    }
  ]
)
