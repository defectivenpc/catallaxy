# The local environment of the two-cluster lab.
#
# Its own subnet and its own host ports, so it stands up beside every other
# lab in this tree rather than fighting them for the network. Nothing else
# differs: the lab is already local.
{ ... }:
{
  lab.name = "homelab.local";

}
