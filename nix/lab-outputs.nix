/*
  Every flake output that is one attribute per lab.

  - `labs.<name>` — the evaluated config, for example labs only. This and
    `labPackages` are the two the CLI resolves; see `lib/lower/lab.nix`.
  - `labPackages.<name>` — the rendered tree, `nix build` reads this.
  - `labPlans.<name>` — `{ deploymentPlan, teardownPlan }`, which the plan
    snapshots are taken from.

  Fixtures are in `labPackages` and `labPlans` but not `labs`: a fixture has
  no cliConfig to resolve and `cata lab list` must not offer one. They are
  here at all so that refreshing a fixture's digest or plan is
  `nix build .#labPackages."<fixture>"`, the same as for a lab.
*/
{
  lib,
  labDefs,
  exampleLabs,
}:

let
  perLab = f: lib.mapAttrs (_: f) labDefs;
in
{
  labs = lib.mapAttrs (_: l: l.cliConfig) exampleLabs;

  labPackages = perLab (l: l.package);

  labPlans = perLab (l: {
    inherit (l) deploymentPlan teardownPlan;
  });
}
