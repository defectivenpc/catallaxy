/*
  The document's shape, from one definition and held to the real documents.

  Two halves, and both are needed.

  `lib/document/generated.nix` must match what `cata-build document` emits, so
  the Rust types stay the definition: add a field to `LabSpec` and this fails
  until the type is regenerated. That is the same net as `generated-types`, for
  the same reason.

  Then every committed cli-config must *conform* to it. That is what says the
  two halves of the document agree in fact rather than on paper — a field Nix
  emits that the parser does not declare fails here naming the field, which is
  the drift nothing caught before, and it found three on its first run.
*/
{
  lib,
  pkgs,
  floeCore,
  cata,
  cliConfigDir,
}:

let
  document = import ../../lib/document/generated.nix { T = floeCore.T; };

  configs = lib.mapAttrs' (
    file: _: lib.nameValuePair (lib.removeSuffix ".json" file) (cliConfigDir + "/${file}")
  ) (lib.filterAttrs (file: _: lib.hasSuffix ".json" file) (builtins.readDir cliConfigDir));

  # Both plans are stripped from the committed copy on purpose, so they are
  # put back as empty — the shape of a plan is pinned by the plan snapshots.
  conforms =
    name: path:
    let
      value = builtins.fromJSON (builtins.readFile path) // {
        deploymentPlan = [ ];
        teardownPlan = [ ];
      };
    in
    builtins.deepSeq (floeCore.conformValue [ name ] document value) "conforms";
in
{
  document-type =
    pkgs.runCommand "document-type"
      {
        nativeBuildInputs = [
          cata
          pkgs.diffutils
          pkgs.nixfmt
        ];
      }
      ''
        ${cata}/bin/cata-build document generated.nix

        # The committed copy is formatted, so the comparison has to be, or
        # every line the formatter touches reads as a change to the shape.
        nixfmt generated.nix

        if ! diff -u ${../../lib/document/generated.nix} generated.nix; then
          echo "" >&2
          echo "The committed document type is not what the Rust types emit." >&2
          echo "" >&2
          echo "The types in cli/src/domain/ are the definition, so this diff is" >&2
          echo "a field added, removed or retyped there. Regenerate it:" >&2
          echo "" >&2
          echo "  cata-build document lib/document/generated.nix" >&2
          exit 1
        fi

        touch $out
      '';
}
// lib.mapAttrs' (
  name: path:
  lib.nameValuePair "document-conforms-${name}" (
    pkgs.runCommand "document-conforms-${name}" { } ''
      echo "${conforms name path}" > $out
    ''
  )
) configs
