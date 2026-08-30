# A lab: clusters built from composed floes, lowered to what `cata` reads.
{ ... }:
{
  imports = [
    ./types.nix
    ./secrets.nix
    ./host
    ./e2e.nix
    ./planner
    ./plan.nix
    ./out.nix
  ];
}
