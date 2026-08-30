# podinfo behind the gateway — the test service.
#
# Two things to notice, and they are the point of the exercise.
#
# The HTTPRoute's `parentRefs` and hostname come out of the sealed
# API_GATEWAY value, so this floe never spells the gateway's name, its
# namespace, its listener, or the lab's DNS zone.
#
# It declares no cross-floe ordering whatsoever — no `needs` reaching outside
# itself, no token naming anything of the gateway's. The edge that puts it
# after the gateway is derived by the elaborator from the link graph and the
# gateway's own `backs`.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "podinfo";

  inputs = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "podinfo";
      description = "Namespace the app installs into. It creates this itself.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/stefanprodan/podinfo:6.7.1";
      description = ''
        Container image. Tag-pinned here; the lab renderer's image lock
        rewrites this to a digest, and that machinery is lab-scope so the
        staged cluster does not get it.
      '';
    };

    replicas = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Replica count.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9898;
      description = "Port the container listens on.";
    };

    servicePort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port the Service publishes, and what the route backends name.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # What the gateway collects. The old `floes.custom` wrote its hostname into
  # `floes.gateway.internalHostnames`; providing it instead means the gateway
  # learns the same fact through an edge the linker checks, and this floe
  # still names nothing of the gateway's.

  out.component = kinds.component;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;

        selector."app.kubernetes.io/name" = "podinfo";
        host = "podinfo.${gateway.baseDomain}";

        # The image arrives as one string because that is how a deployer thinks
        # of it, and the image set wants it in parts. Split here, from the same
        # binding the container uses, so the declaration and what is deployed
        # cannot name different things.
        #
        # Digest-pinned refs are not handled: nothing here passes one, and
        # guessing at `@sha256:` would put a wrong tag in the declaration
        # rather than fail.
        imageParts =
          let
            slash = lib.splitString "/" inputs.image;
            registry = lib.head slash;
            rest = lib.concatStringsSep "/" (lib.tail slash);
            colon = lib.splitString ":" rest;
          in
          {
            inherit registry;
            repository = lib.head colon;
            tag = if lib.length colon > 1 then lib.last colon else null;
          };
      in
      {

        config.floe.out.component = kinds.mkComponent {
          # One container, and it is the one below.
          imagesComplete = true;

          # Reached by the gateway and nothing else. It dials nothing, which
          # is stated rather than left blank so it reads as reviewed.
          network = {
            declared = true;
            serves.http.port = inputs.port;
          };

          bundles.podinfo = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.podinfo = {
              inherit (imageParts) registry repository tag;
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/podinfo";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "3m";
            };

            verify.route-answers = {
              description = "The route through the gateway reaches podinfo";
              timeout = "2m";
              expect = {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata = {
                  name = "podinfo";
                  namespace = inputs.namespace;
                };
                status.readyReplicas = inputs.replicas;
              };
              reject = [ ];
            };

            resources = {
              podinfo-deployment = {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata = {
                  name = "podinfo";
                  inherit (inputs) namespace;
                };
                spec = {
                  inherit (inputs) replicas;
                  selector.matchLabels = selector;
                  template = {
                    metadata.labels = selector;
                    spec.containers = [
                      {
                        name = "podinfo";
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
                        livenessProbe = {
                          httpGet = {
                            path = "/healthz";
                            inherit (inputs) port;
                          };
                          initialDelaySeconds = 5;
                        };
                        resources = {
                          requests = {
                            cpu = "10m";
                            memory = "32Mi";
                          };
                          limits.memory = "128Mi";
                        };
                      }
                    ];
                  };
                };
              };

              podinfo-service = {
                apiVersion = "v1";
                kind = "Service";
                metadata = {
                  name = "podinfo";
                  inherit (inputs) namespace;
                };
                spec = {
                  inherit selector;
                  ports = [
                    {
                      name = "http";
                      port = inputs.servicePort;
                      targetPort = inputs.port;
                    }
                  ];
                };
              };

              # The gateway's own constructor, so the shape of a route and the
              # check that it is in-zone live with the floe that serves it.
              podinfo-route = kinds.mkRoute {
                inherit gateway;
                name = "podinfo";
                inherit (inputs) namespace;
                service = "podinfo";
                port = inputs.servicePort;
              };
            };
          };
        };
      }
    )
  ];
}
