# Domain signatures for the example deployment.
{ floe }:

let
  T = floe.T;
in
{
  INGRESS = floe.mkSig {
    name = "INGRESS";
    fields = {
      baseDomain = T.dnsName;
      className = T.str;
      # Only exists after apply; typed as deferred so eval-time misuse is an error.
      address = T.deferred T.str;
    };
  };

  OBSERVER = floe.mkSig {
    name = "OBSERVER";
    fields = {
      ingressUrl = T.url;
      dashboards = T.attrsOf (T.record { url = T.url; });
    };
  };

  DASHBOARD_REQ = floe.mkSig {
    name = "DASHBOARD_REQ";
    fields = {
      app = T.k8sName;
      panels = T.listOf T.str;
    };
  };
}
