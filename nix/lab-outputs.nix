/*
  Every flake output that is one attribute per lab.

  - `labs.<name>` — the evaluated config, for example labs only. This and
    `labPackages` are the two the CLI resolves; see `lib/lower/lab.nix`.
  - `labPackages.<name>` — the rendered tree, `nix build` reads this.
  - `labPlans.<name>` — `{ deploymentPlan, teardownPlan }`, which the plan
    snapshots are taken from.
  - `clusters.<name>.<cluster>` — the cluster's spec beside its manifests.
  - `clusterPictures.<name>.<cluster>` — what the cluster floe output.
  - `digestLabs` — the names a digest is committed for, labs and fixtures
    both.

  Fixtures are in all of these but `labs`, because a fixture has no cliConfig
  to resolve and `cata lab list` must not offer one.
*/
{
  lib,
  pkgs,
  labDefs,
  exampleLabs,
}:

let
  perLab = f: lib.mapAttrs (_: f) labDefs;
  perCluster = f: perLab (l: lib.mapAttrs f l.clusters);
in
{
  labs = lib.mapAttrs (_: l: l.cliConfig) exampleLabs;

  labPackages = perLab (l: l.package);

  labPlans = perLab (l: {
    inherit (l) deploymentPlan teardownPlan;
  });

  clusters = perCluster (
    name: c:
    pkgs.runCommand "cluster-${name}" { } ''
      mkdir -p $out
      cp ${pkgs.writeText "cluster.json" (builtins.toJSON c.spec)} $out/cluster.json
      ln -s ${c.manifests} $out/manifests
    ''
  );

  clusterPictures = perCluster (_: c: c.out);

  digestLabs = lib.attrNames labDefs;
}
