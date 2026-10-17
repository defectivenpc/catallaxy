/*
  The generated Kubernetes and CRD types, as derivations.

      nix build .#generatedTypes                 # every floe's crds/
      nix build .#floeTypes.cert-manager         # one floe's crds/<group>.nix

  One binding, so the check and whatever refreshes the committed tree read the
  same store path. Producing the fixture and the check from two pipelines would
  let them disagree about the very thing one exists to check.

  `cata-build generate` writes `<floe>/crds/<group>.json`: each floe's CRD
  schemas, under the floe that installs them. The copy out mirrors that, so the
  layout here is the layout in the tree.

  The Kubernetes API is not here. `lib/kubernetes/schema-to-type.nix` converts
  the pinned OpenAPI spec at evaluation time, which is why `k8s/` is gone and
  77,623 lines of generated Nix with it. JSON rather than Nix for the same
  reason: the only thing generation buys a CRD is the format change Nix forces,
  since it has no `fromYAML`.

  Per floe as well as whole. A floe owns its pin and its committed types, so
  regenerating one must not mean regenerating all of them — and a floe outside
  this repository has no aggregate to be part of. `generatedTypes` fans out to
  the same per-floe derivations rather than calling the generator once, so the
  two cannot drift.
*/
{
  lib,
  pkgs,
  cata,
  crdSources,
}:

let
  generate =
    name: config:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          cata
        ];
        json = builtins.toJSON ({ outputDir = "out"; } // config);
        passAsFile = [ "json" ];
      }
      ''
        mkdir -p $out
        cata-build generate "$jsonPath" --output $out

        # JSON, so there is nothing to format: `cata-build generate` writes it
        # pretty-printed with stable key order.
      '';

  # Each floe's groups, generated from that floe's artifact alone. The
  # generator still refuses two sources claiming one `group/Kind`, but it only
  # ever sees one source here — `floe-upstream` is what refuses a group
  # claimed by two floes now.
  floeTypes = lib.mapAttrs (
    floe: yaml: generate "generated-types-${floe}" { crds.${floe} = "${yaml}"; }
  ) crdSources;
in
{
  inherit floeTypes;

  # The same per-floe outputs, assembled into the shape the committed tree
  # has, which is what `generated-types` diffs against.
  all = pkgs.runCommand "generated-types" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (floe: drv: ''
        cp -r ${drv}/${floe} $out/${floe}
      '') floeTypes
    )
  );
}
