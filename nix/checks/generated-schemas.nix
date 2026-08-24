{
  lib,
  pkgs,
  k8sTypegenConfig,
}:

let
  generated = ../../modules/lab/cluster/lib/kubernetes/generated;

  sanitize = builtins.replaceStrings [ "." "-" ] [ "_" "_" ];

  nixFilesIn =
    dir:
    lib.sort (a: b: a < b) (
      map (lib.removeSuffix ".nix") (
        builtins.attrNames (
          lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir dir)
        )
      )
    );

  expected = names: lib.sort (a: b: a < b) (lib.unique (map sanitize (builtins.attrNames names)));

  compare =
    what: onDisk: wanted:
    let
      stale = lib.subtractLists wanted onDisk;
      missing = lib.subtractLists onDisk wanted;
    in
    lib.optional (
      stale != [ ]
    ) "${what} on disk that nothing generates: ${lib.concatStringsSep ", " stale}"
    ++
      lib.optional (missing != [ ])
        "${what} the generator would write but that are not committed: ${lib.concatStringsSep ", " missing}";

  failures =
    compare "CRD schema files" (nixFilesIn (generated + "/crds")) (expected k8sTypegenConfig.crds)
    ++ compare "Kubernetes schema files" (nixFilesIn (generated + "/k8s")) (
      expected k8sTypegenConfig.k8sVersions
    );
  inherit (import ./report.nix { inherit lib pkgs; }) mkCheck;
in
{
  generated-schemas-match-their-sources = mkCheck {
    what = "generated-schemas-match-their-sources";
    passed = "every generated schema file has a source, and every source has a file";
    why = ''
      The committed Kubernetes schemas no longer match what generates them.

      `lib/k8s-specs.nix` derives the input set from `lib/charts.nix`: every
      chart with a `crd` definition, plus the standalone CRD bundles. Adding
      a chart, removing one, or renaming its key changes that set, and the
      committed tree only follows when the generator is run.

      The two ways this goes wrong are opposite and both silent. A file with
      no source is a schema for a chart the lab no longer ships, and it keeps
      validating resources against a version nothing installs. A source with
      no file is a CRD whose kinds fall back to unchecked attrs, which looks
      exactly like a resource that has no schema at all.

      This compares the *set of files*, not their contents: a committed schema
      can be stale against the chart it came from and still pass here.
    '';
    fix = ''
      Run `nix run .#generate-k8s-types`, then `nix fmt`, and commit the
      result. Delete any file the run does not rewrite.
    '';
    inherit failures;
  };
}
