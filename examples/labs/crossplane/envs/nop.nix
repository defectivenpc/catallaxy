# The provider that reaches nothing, which is what makes this lab runnable.
{ ... }:

{
  lab.name = "crossplane.nop";

  # Its own subnet and ports, so it stands beside every other lab on one
  # docker host. `nix/checks/lab-checks.nix` refuses an overlap.
}
