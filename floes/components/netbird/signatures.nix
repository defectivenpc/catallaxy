{ lib, floe }:

let
  T = floe.T;
in
rec {
  MESH_NETWORK = floe.mkSig {
    name = "MESH_NETWORK";
    canonicalName = "mesh";

    description = "A mesh control plane, addressed from inside the cluster running it and from outside.";

    fields = {
      namespace = T.k8sName;

      managementUrl = T.str;
      managementInternalUrl = T.str;

      dashboardUrl = T.str;
    };
  };

  MESH_NETWORK_SHARED = floe.project {
    signature = MESH_NETWORK;
    fields = [
      "managementUrl"
      "dashboardUrl"
    ];
    description = "A mesh control plane as a cluster that does not run it can address it.";
  };

  MESH_ADMIN = floe.mkSig {
    mayExport = false;
    name = "MESH_ADMIN";
    canonicalName = "meshAdmin";
    description = "The credential that administers the mesh, as a Secret only its own cluster can read.";
    fields = {
      tokenSecret = (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );
    };
  };
}
