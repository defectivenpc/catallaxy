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
    summary = "A minimal cluster example.";

    inputs = {
      tls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the gateway terminates TLS.";
      };
    };

    requires = {
      cluster = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;
    };

    optional.labCa = sigs.LAB_CA;

    optional.edge = sigs.CLUSTER_EDGE;

    provides = {
      delivery = sigs.DELIVERY_POLICY;

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

  appWithCredentials = mkClusterFloe {
    name = "minimal-app-credentials";
    summary = "The `minimal` cluster, with lab-held credentials projected into it.";

    requires = {
      cluster = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;

      # What the projection below reads. A hole, because the values are the
      # lab's and no cluster can mint them — and declaring it is what replaced
      # a `source = "app-credentials"` string naming an attribute nothing
      # checked.
      labSecret = sigs.LAB_SECRET;
    };

    provides.delivery = sigs.DELIVERY_POLICY;
    exports.delivery = "app/delivery";

    units = _: {
      app = app { };

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

  appWithCilium = mkClusterFloe {
    name = "minimal-app-cilium";
    summary = "The `minimal` cluster, with Cilium as its CNI.";

    requires = {
      cluster = sigs.KUBERNETES_CLUSTER;
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
