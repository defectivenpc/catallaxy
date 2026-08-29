# The floes catallaxy ships, as name -> path.
#
# An attribute set rather than an import list, so a consumer can `removeAttrs`
# one or substitute their own. Membership is explicit: adding a floe means
# adding a line here, which is what keeps a check able to say which floes it
# checked.
{
  cluster = {
    gateway = ./cluster/gateway;
    gateway-api-crds = ./cluster/gateway-api-crds;
    podinfo = ./cluster/podinfo;
  };

  provisioners = {
    k3d-cluster = ./provisioners/k3d-cluster.nix;
  };
}
