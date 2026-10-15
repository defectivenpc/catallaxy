/*
  The generated Kubernetes and CRD types, as a derivation.

  One binding, so the check and whatever refreshes the committed tree read the
  same store path. Producing the fixture and the check from two pipelines would
  let them disagree about the very thing one exists to check.

  `cata-build generate` writes `k8s/<version>.nix` and `<floe>/crds/<group>.nix`:
  the Kubernetes API in one place, and each floe's CRD types under the floe that
  installs them. The copy out mirrors that, so the layout here is the layout in
  the tree.

  It no longer writes `index.nix`. The only generated thing in that file was the
  list of CRD group files, and the groups arrive as an argument now.
*/
{
  lib,
  pkgs,
  cata,
  k8sSpecs,
  crdSources,
}:

let
  config = pkgs.writeText "cata-generate.json" (
    builtins.toJSON {
      outputDir = "out";
      k8sVersions = lib.mapAttrs (_: spec: "${spec}") k8sSpecs.specs;
      crds = lib.mapAttrs (_: yaml: "${yaml}") crdSources;
    }
  );
in
pkgs.runCommand "generated-types"
  {
    nativeBuildInputs = [
      cata
      pkgs.nixfmt
    ];
  }
  ''
    mkdir -p $out
    cata-build generate ${config} --output $out

    # The committed tree is formatted, so the comparison has to be. Without
    # this the check reports a diff on every line the formatter would touch and
    # says nothing about whether the types changed.
    nixfmt $out/k8s/*.nix $out/*/crds/*.nix
  ''
