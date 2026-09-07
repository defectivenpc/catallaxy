# The step-kind table, and the copy of it the CLI tests against.
#
# `cli/src/domain/step_kind_conformance.rs` reads
# `cli/tests/fixtures/step-kinds.json` and asserts that every kind Nix
# declares deserialises into its Rust variant, that every optional param is
# accepted and every required one required. That test is only as good as the
# fixture, and until now nothing regenerated it: the fixture was a snapshot of
# a table that has since moved.
#
# This closes the loop. Nix owns the table; the fixture is derived from it;
# and a kind added on one side without the other fails here rather than at
# apply, where a mistyped param reads as a step that silently does nothing.
{
  lib,
  pkgs,
}:

let
  schema = import ./step-kind-schema.nix { inherit lib; };
  generated = pkgs.writeText "step-kinds.json" (builtins.toJSON schema);
in
{
  step-kinds =
    pkgs.runCommand "step-kinds"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.diffutils
        ];
      }
      ''
        # Both sides through jq, so the comparison is of the data and not of
        # how two serialisers chose to order keys or space separators.
        jq -S . ${generated} > $TMPDIR/generated.json
        jq -S . ${../../cli/tests/fixtures/step-kinds.json} > $TMPDIR/committed.json

        if ! diff -u $TMPDIR/committed.json $TMPDIR/generated.json; then
          echo "" >&2
          echo "The step-kind table and the fixture the CLI tests against disagree." >&2
          echo "" >&2
          echo "Every kind Nix declares has a Rust variant that must accept its" >&2
          echo "params. The conformance test proves that against the fixture, so a" >&2
          echo "stale fixture proves it against a table nobody ships." >&2
          echo "" >&2
          echo "Refresh it:" >&2
          echo "  nix eval --json --impure --expr '(import ./nix/checks/step-kind-schema.nix" >&2
          echo "    { lib = (import <nixpkgs> {}).lib; })' | jq -S . > cli/tests/fixtures/step-kinds.json" >&2
          exit 1
        fi
        touch $out
      '';
}
