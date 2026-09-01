# The local environment of the two-cluster lab.
#
# Its own subnet and its own host ports, so it stands up beside every other
# lab in this tree rather than fighting them for the network. Nothing else
# differs: the lab is already local.
{ ... }:
{
  lab.name = "homelab.local";

  lab.network.subnet = "172.34.0.0/16";

  lab.proxy.httpPort = 8084;
  lab.proxy.httpsPort = 8447;
  lab.dns.hostPort = 5360;
  lab.registry.port = 5056;
  lab.egress.port = 3133;
}
