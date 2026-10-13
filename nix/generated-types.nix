/*
  The generated Kubernetes and CRD types, as a derivation.

  One binding, two readers: `generated-types` diffs the committed tree against
  this, and `refresh-generated-types` copies out of it. Producing the fixture
  and the check from two pipelines would let them disagree about the very thing
  one exists to check.

  `cata-build generate` writes `k8s/`, `crds/` and `index.nix` in one pass, because
  `index.nix` names both halves — so there is no generating one without the
  other, and no separate refresh per half.
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
    nixfmt $out/index.nix $out/k8s/*.nix $out/crds/*.nix
  ''
