# The cluster `minimal` stands up, as a floe.
#
# Three units and two holes, which is the whole of what this lab's cluster is.
# `standard-cluster` is the platform — the CRDs, an issuer, trust, in-cluster
# DNS and a gateway — and this adds a workload and says how content reaches
# the cluster.
#
# It used to be six floes written out in `lab.nix` with `minimal.tls` adding
# two more and overriding two: `gateway-api-crds`, `cert-manager` and
# `gateway` by hand here, `coredns-zone` and `trust-manager` there, which is
# `standard-cluster` reassembled one floe at a time. One inclusion instead,
# with the two facts that differ as inputs.
#
# Both holes are open on purpose. The claim, because that is what lets
# `minimal.talos` be the same cluster on a different provisioner — the
# components resolve against the hole, never against the thing that fills it.
# The zone, because it is a fact the lab holds and no cluster can derive.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
rec {
  app = mkClusterFloe {
    name = "minimal-app";
    summary = "A platform, one routed workload, and an apply `cata` performs.";

    inputs = {
      tls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the gateway terminates TLS.";
      };

    };

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    # Where this cluster is dialled, which the claim answers because only the
    # tool that created the cluster knows its container names. Declared
    # because this cluster is fronted: it travels out again inside the
    # exposure below, so the ingress gets the hostnames and the address
    # together.
    # The lab's root, so the issuer in here signs from it rather than minting
    # a second. It was `rootFromLab = true` threaded down two levels.
    optional.labCa = sigs.LAB_CA;

    optional.edge = sigs.CLUSTER_EDGE;

    # The one thing a lab needs of a cluster that the cluster is the only
    # thing that can say: how its content reaches it. Read off the export
    # rather than out of the units, because an inclusion seals.
    provides = {
      delivery = sigs.DELIVERY_POLICY;

      # What the lab's resolver answers for. Exported because this lab fronts
      # this cluster; a cluster that is its own edge withholds it, and that is
      # the whole of how the difference is said. ADR 0004.
      exposure = sigs.HOST_EXPOSURE;
    };

    exports = {
      delivery = "kapp/delivery";
      exposure = "platform/exposure";
    };

    units =
      { inputs, ... }:
      {
        kapp = floes.kapp { };

        platform = floes.standard-cluster { inherit (inputs) tls; };

        podinfo = floes.podinfo { };
      };
  };

  # `minimal.secrets` is a different cluster, not this one with a flag: it
  # holds material the lab authored and lands it as a Secret in the namespace
  # that consumes it. Including `app` rather than copying it is the closure
  # property — linking units yields a unit — so what this adds is visible as
  # the one line it is.
  appWithCredentials = mkClusterFloe {
    name = "minimal-app-credentials";
    summary = "The `minimal` cluster, with lab-held credentials projected into it.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;

      # What the projection below reads. A hole, because the values are the
      # lab's and no cluster can mint them — and declaring it is what replaced
      # a `source = "app-credentials"` string naming an attribute nothing
      # checked.
      secret = sigs.LAB_SECRET;
    };

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "app/delivery";

    units = _: {
      app = app { };

      # `podinfo` is the namespace anything here would consume it from.
      app-credentials = floes.secret-projection {
        secret = "app-credentials";
        namespace = "podinfo";
        keys = {
          token.from = "api-token";
          session.from = "session-key";
        };
      };
    };
  };

  # `minimal.cilium` likewise: a cluster whose network is Cilium rather than
  # the provisioner's default. The floe provides `CNI_BOOTSTRAP` and this
  # exports it, which is how the *claim* — a unit beside this one — gets the
  # manifest it has to apply before any node is Ready. Nothing here sets
  # `disableFlannel`, and nothing templates a chart: both halves are one
  # floe's, and they cannot disagree about what is running.
  appWithCilium = mkClusterFloe {
    name = "minimal-app-cilium";
    summary = "The `minimal` cluster, with Cilium as its CNI.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    provides = {
      delivery = sigs.DELIVERY_POLICY;
      cniBootstrap = sigs.CNI_BOOTSTRAP;
    };

    exports = {
      delivery = "app/delivery";
      cniBootstrap = "cilium/cniBootstrap";
    };

    units = _: {
      app = app { };
      cilium = floes.cilium { };
    };
  };
}
