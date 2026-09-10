# A lab: clusters built from composed floes, lowered to what `cata` reads.
{ ... }:
{
  imports = [
    ./types.nix
    ./secrets.nix
    ./host
    ./e2e.nix
    ./e2e-cloud.nix
    ./cd.nix
    ./planner
    ./plan.nix
    ./out.nix
  ];
}
