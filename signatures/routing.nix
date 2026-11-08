{ lib, floe }:

let
  T = floe.T;

  edgeTarget = {
    backend = T.str;
    httpPort = T.port;
    httpsPort = T.port;
  };
in
{
  GATEWAY_API = floe.mkSig {
    name = "GATEWAY_API";
    canonicalName = "gatewayApi";
    description = "The Gateway API CRDs are registered, so Gateway and route kinds have types.";
    fields = {
      version = T.str;
      crdKinds = (T.listOf T.str);
    };
  };

  API_GATEWAY = floe.mkSig {
    name = "API_GATEWAY";
    canonicalName = "gateway";

    behaviour = [ "gateways-programmed" ];
    description = "An ingress a workload attaches an HTTPRoute to, and the zone its hostnames live in.";
    fields = {
      className = T.str;
      baseDomain = T.dnsName;
      parentRef = (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
          sectionName = T.str;
        }
      );
    };
  };

  CLUSTER_EDGE = floe.mkSig {
    name = "CLUSTER_EDGE";
    canonicalName = "edge";
    description = "Where a cluster's gateway is dialled from the host running the lab.";
    fields = edgeTarget;
  };

  ROUTE_CLAIM = floe.mkSig {
    name = "ROUTE_CLAIM";
    canonicalName = "route";
    description = "A public hostname this floe publishes, for whoever answers for the zone.";
    fields = {
      host = T.dnsName;
    };
  };

  HOST_EXPOSURE = floe.mkSig {
    name = "HOST_EXPOSURE";
    canonicalName = "exposure";
    description = "The hostnames a cluster serves through the lab's edge, and where to dial them.";
    fields = {
      hosts = T.listOf T.dnsName;

      edge = T.nullOr (T.record edgeTarget);
    };
  };
}
