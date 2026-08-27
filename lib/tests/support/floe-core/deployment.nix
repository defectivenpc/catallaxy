# A three-unit deployment: ingress, grafana, myapp.
{
  lib,
  floe,
  floes,
  policies,
}:

floe.link {
  units = {
    ingress = floes.nginxIngress.instantiate {
      baseDomain = "lab.example.com";
    };
    grafana = floes.grafana.instantiate {
      size = "50Gi";
      adminUser = "michael";
    };
    myapp = floes.myapp.instantiate { };
  };
  policies = [ policies.noEnvMixing ];
}
