# The cluster `gitops.local` stands up, as a floe.
#
# The platform plus the two floes that make this lab what it is: a git remote
# to read from and a CD tool that takes the apply over. There is no `kapp`
# here, which is the point — `argocd` answers `DELIVERY_POLICY` instead, and
# `policies.oneDelivery` is what refuses a cluster that answers twice or not
# at all.
#
# It used to write out `gateway-api-crds`, `cert-manager`, `trust-manager`,
# `coredns-zone`, `gateway` and `external-secrets` by hand, which is
# `standard-cluster` reassembled with `tls` already decided.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  app = mkClusterFloe {
    name = "gitops-app";
    summary = "A platform behind TLS, a git remote, and Argo CD applying from it.";

    requires = {
      cluster = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;

      # Somewhere for forgejo to bind a PVC. Answered by the claim, because
      # whether a provisioner ships a default storage class is its to say.
      storageClass = sigs.STORAGE_CLASS;
    };

    # Where the cluster is dialled, answered by its claim.
    # The lab's root, so the issuer in here signs from it rather than minting
    # a second. It was `rootFromLab = true` threaded down two levels.
    optional.labCa = sigs.LAB_CA;

    optional.edge = sigs.CLUSTER_EDGE;

    # Two things the lab needs of this cluster and only this cluster can say:
    # how its content reaches it, and where the repository Argo reads lives.
    # `modules/lab/cd.nix` finds both by signature off the boundary rather
    # than by reaching into the units, which is what sealing is for.
    provides = {
      delivery = sigs.DELIVERY_POLICY;
      git = sigs.GIT_REPOSITORY;

      # What the lab's resolver answers for. ADR 0004.
      exposure = sigs.HOST_EXPOSURE;
    };

    exports = {
      delivery = "argocd/delivery";
      git = "forgejo/git";
      exposure = "platform/exposure";
    };

    units = _: {
      platform = floes.standard-cluster {
        tls = true;
      };

      forgejo = floes.forgejo { };
      argocd = floes.argocd { };
      podinfo = floes.podinfo { };
    };
  };
}
