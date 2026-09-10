# The local environment of the minimal lab.
#
# An environment is the same lab with different settings. Everything the lab
# declares with `mkDefault` is what an environment may change.
{ ... }:
{
  lab.name = "minimal.local";
  lab.network.subnet = "172.20.0.0/16";
}
