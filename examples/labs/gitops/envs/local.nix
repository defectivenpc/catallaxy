# The gitops lab as it runs: its own subnet and host ports, nothing else
# differing. The lab is already local.
{ lab, ... }:

lab {
  name = "gitops.local";
}
