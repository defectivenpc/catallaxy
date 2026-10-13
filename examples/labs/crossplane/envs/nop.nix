# The provider that reaches nothing, which is what makes this lab runnable.
#
# Its own subnet and ports, so it stands beside every other lab on one docker
# host. `nix/checks/lab-checks.nix` refuses an overlap.
{ lab, ... }:

lab {
  name = "crossplane.nop";
}
