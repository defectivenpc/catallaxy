# `cata` applies the manifests itself.
#
# It installs nothing, and that is the point: a cluster has to *say* how its
# content reaches it, and until this existed the answer "kapp" was what a lab
# got when nothing said anything at all. Absence of a provider meant the
# default, so a lab that meant to run Argo and forgot to add it was a lab
# `cata` quietly applied by hand — and a cluster's document asserted a
# strategy nothing in the cluster had chosen.
#
# So this is the floe for the ordinary case, and holding it beside a CD tool
# is two providers of one signature, which the linker refuses by name. That
# refusal is the question being asked: which of these applies this cluster?
{
  floe,
  lib,
  sigs,
  ...
}:

floe.mkFloe {
  name = "kapp";
  summary = "`cata` applies this cluster's manifests, with kapp.";

  inputs.waitTimeout = lib.mkOption {
    type = lib.types.str;
    default = "10m";
    description = ''
      How long an apply may take to settle before it is called failed.

      Belongs to whatever applies — kapp here, Argo elsewhere — rather than
      to the cluster or to the host: it is a property of the process doing
      the waiting. The host's own patience, for an API server to answer
      during provisioning, is `lab.clusters.<c>.waitTimeout`.
    '';
  };

  # The cluster it applies to, so the policy can carry the context whatever is
  # at lab scope addresses it by. `kapp` required nothing before, which was
  # true of what it *installs* and not of what it describes.
  requires.cluster = sigs.KUBERNETES_CLUSTER;

  provides.delivery = sigs.DELIVERY_POLICY;

  body =
    { inputs, requires, ... }:
    {
      provides.delivery = {
        strategy = "kapp";

        bootstrapTool = "kubectl-ssa";

        inherit (inputs) waitTimeout;
        inherit (requires.cluster) context;
      };
    };
}
