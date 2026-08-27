# Consumes OBSERVER without knowing it is grafana, and provides its own
# DASHBOARD_REQ (which grafana collects via requiresMany). Note the mutual
# reference: myapp requires OBSERVER from grafana while grafana's fan-in hole
# collects myapp's DASHBOARD_REQ. Laziness resolves it because neither
# provide's fields depend on the other unit's provides.
{
  floe,
  sigs,
  kinds,
  lib,
}:

floe.mkFloe {
  name = "myapp";

  requires.observer = sigs.OBSERVER;
  provides.dashboardReq = sigs.DASHBOARD_REQ;
  out = {
    k8s = kinds.k8s;
    meta = kinds.meta;
  };

  modules = [
    ({ config, ... }: {
      config.floe.provides.dashboardReq = {
        app = "myapp";
        panels = [
          "http_requests_total"
          "latency_p99"
        ];
      };

      config.floe.out.k8s.deployment = {
        apiVersion = "apps/v1";
        kind = "Deployment";
        metadata = {
          name = "myapp";
          annotations."runbook/dashboard" = config.floe.requires.observer.dashboards.myapp.url;
        };
      };

      config.floe.out.meta = {
        cluster = "internal";
        environment = "lab";
      };
    })
  ];
}
