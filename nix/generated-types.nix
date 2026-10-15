/*
  The generated Kubernetes and CRD types, as derivations.

      nix build .#generatedTypes                 # k8s/ and every floe's crds/
      nix build .#floeTypes.cert-manager         # one floe's crds/<group>.nix

  One binding, so the check and whatever refreshes the committed tree read the
  same store path. Producing the fixture and the check from two pipelines would
  let them disagree about the very thing one exists to check.

  `cata-build generate` writes `k8s/<version>.nix` and `<floe>/crds/<group>.nix`:
  the Kubernetes API in one place, and each floe's CRD types under the floe that
  installs them. The copy out mirrors that, so the layout here is the layout in
  the tree.

  Per floe as well as whole. A floe owns its pin and its committed types, so
  regenerating one must not mean regenerating all of them — and a floe outside
  this repository has no aggregate to be part of. `generatedTypes` fans out to
  the same per-floe derivations rather than calling the generator once, so the
  two cannot drift.

  It writes no `index.nix`. The only generated thing in that file was the list
  of CRD group files, and the groups arrive as an argument now.
*/
{
  lib,
  pkgs,
  cata,
  k8sSpecs,
  crdSources,
}:

let
  generate =
    name: config:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          cata
          pkgs.nixfmt
        ];
        json = builtins.toJSON ({ outputDir = "out"; } // config);
        passAsFile = [ "json" ];
      }
      ''
        mkdir -p $out
        cata-build generate "$jsonPath" --output $out

        # The committed tree is formatted, so the comparison has to be. Without
        # this the check reports a diff on every line the formatter would touch
        # and says nothing about whether the types changed.
        find $out -name '*.nix' -exec nixfmt {} +
      '';

  # Each floe's groups, generated from that floe's artifact alone. The
  # generator still refuses two sources claiming one `group/Kind`, but it only
  # ever sees one source here — `floe-upstream` is what refuses a group
  # claimed by two floes now.
  floeTypes = lib.mapAttrs (
    floe: yaml: generate "generated-types-${floe}" { crds.${floe} = "${yaml}"; }
  ) crdSources;

  k8sTypes = generate "generated-types-k8s" {
    k8sVersions = lib.mapAttrs (_: spec: "${spec}") k8sSpecs.specs;
  };
in
{
  inherit floeTypes k8sTypes;

  # The same per-floe outputs, assembled into the shape the committed tree
  # has, which is what `generated-types` diffs against.
  all = pkgs.runCommand "generated-types" { } (
    ''
      mkdir -p $out
      cp -r ${k8sTypes}/k8s $out/k8s
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (floe: drv: ''
        cp -r ${drv}/${floe} $out/${floe}
      '') floeTypes
    )
  );
}
