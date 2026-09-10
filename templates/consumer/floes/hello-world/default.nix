# A worked example: one Deployment, one Service, routed by the lab's gateway.
#
# The thing to copy is `requires.gateway`. This floe never spells the
# gateway's name, namespace, listener, or the lab's DNS zone — it reads them
# off the sealed value, and the edge that orders it after the gateway is
# derived from that link rather than declared here.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "hello-world";
  summary = "A single routed workload, as a starting point for your own floes.";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "hello-world";
      description = "Namespace it installs into. It creates this itself.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/stefanprodan/podinfo:6.7.1";
      description = ''
        Container image, tag-pinned. The lab renderer's image lock rewrites
        this to a digest.
      '';
    };

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Replica count.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9898;
      description = "Port the container listens on.";
    };
  };

  requires.gateway = sigs.API_GATEWAY;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;

        selector."app.kubernetes.io/name" = "hello-world";
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.hello-world = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.hello-world = kinds.mkImage inputs.image;

            ready = kinds.readyDeployment {
              name = "hello-world";
              namespace = inputs.namespace;
              timeout = "3m";
            };

            resources = {
              deployment = {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata = {
                  name = "hello-world";
                  inherit (inputs) namespace;
                };
                spec = {
                  inherit (inputs) replicas;
                  selector.matchLabels = selector;
                  template = {
                    metadata.labels = selector;
                    spec.containers = [
                      {
                        name = "hello-world";
                        inherit (inputs) image;
                        ports = [
                          {
                            name = "http";
                            containerPort = inputs.port;
                          }
                        ];
                        readinessProbe = {
                          httpGet = {
                            path = "/readyz";
                            inherit (inputs) port;
                          };
                          initialDelaySeconds = 2;
                        };
                      }
                    ];
                  };
                };
              };

              service = {
                apiVersion = "v1";
                kind = "Service";
                metadata = {
                  name = "hello-world";
                  inherit (inputs) namespace;
                };
                spec = {
                  selector = selector;
                  ports = [
                    {
                      name = "http";
                      port = 80;
                      targetPort = inputs.port;
                    }
                  ];
                };
              };

              route = {
                apiVersion = "gateway.networking.k8s.io/v1";
                kind = "HTTPRoute";
                metadata = {
                  name = "hello-world";
                  inherit (inputs) namespace;
                };
                spec = {
                  parentRefs = [ gateway.parentRef ];
                  hostnames = [ "hello-world.${gateway.baseDomain}" ];
                  rules = [
                    {
                      backendRefs = [
                        {
                          name = "hello-world";
                          port = 80;
                        }
                      ];
                    }
                  ];
                };
              };
            };
          };
        };
      }
    )
  ];
}
