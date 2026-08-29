# gateway, ported to the floe interface.
#
# Spike artefact, beside ./default.nix the way ./modular.nix sits beside
# ./default.nix in reloader — `lib/tests/floe-port-equivalence.nix` evaluates
# both and asserts they produce the same data.
#
# reloader proved the mechanism on a small floe that reads nothing and writes
# only its own bundles. gateway is the one that finds what is missing, and it
# found three things the spike had not:
#
#   1. **Cluster reads.** `config.cluster.provisionerOut.publishesGatewayPorts`
#      and `config.cluster.network.serviceSubnet` are reads of the *cluster*,
#      not of a floe, and `config` here is the floe. They arrive as a `cluster`
#      module argument, the read-only twin of `lab`.
#
#   2. **Cluster writes.** `cluster.ingress` and `cluster.prerequisites` are
#      declared on the interface and folded upward, the way `bundles` already
#      is. Written flat (`ingress`, `prerequisites`) because `cluster` is now
#      the name of the read channel and one name cannot be both.
#
#   3. **Sibling writes, which are still unsolved.** Four floes write
#      `floes.gateway.internalHostnames`. `peers` carries exports outward and
#      has no inbound direction. See the note on that option in
#      ./modular-options.nix.
#
# Everything else is the same two mechanical rewrites as reloader:
# `floes.gateway.<x>` becomes `<x>`, and `cfg.<x>` becomes `config.<x>`.
{
  config,
  lib,
  cluster,
  cataCharts,
  k8sSpecs,
  contracts,
  lab,
  peers,
  ...
}:

let
  verifyTypes = import ../../../modules/lab/verify-types.nix { inherit lib; };
in
{
  imports = [ ./modular-options.nix ];

  options.exports = lib.mkOption {
    type = lib.types.submodule {
      options = {
        routing = (import ../../../lib/contracts/routing.nix { inherit lib; }).routingOption;

        className = lib.mkOption {
          type = lib.types.str;
          default = "traefik";
          description = "GatewayClass name.";
        };
        namespace = lib.mkOption {
          type = lib.types.str;
          default = "kube-system";
          description = "Gateway namespace.";
        };
        gatewayName = lib.mkOption {
          type = lib.types.str;
          default = "default-gateway";
          description = "Public Gateway resource name.";
        };
        defaultTier = lib.mkOption {
          type = lib.types.enum [
            "public"
            "internal"
          ];
          default = "public";
          description = ''
            Network tier a gateway-exposed floe attaches to unless it sets
            `gateway.tier` itself.

            Read this rather than `lab.policy.exposure.defaultTier`. The
            gateway floe owns what exposure means, so it is the one place
            that reads the lab policy, and a floe that wants the default
            tier depends on the gateway rather than assuming a lab shape.
          '';
        };
        passthroughEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the TLS passthrough listener is enabled.";
        };
        terminatingListenerName = lib.mkOption {
          type = lib.types.str;
          default = "https";
          description = ''
            Listener a plain (non-passthrough) HTTPRoute should name in
            `parentRefs.sectionName`. `https` when TLS terminates here,
            `http` when it does not: a lab with `tls.enable = false`
            has no `https` listener, so a route pinned to it attaches to
            nothing (`NoMatchingParent`) and the gateway 404s.
          '';
        };
        passthroughPort = lib.mkOption {
          type = lib.types.port;
          default = 8444;
          description = "Passthrough entryPoint port on Traefik.";
        };
        internalEnabled = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the internal-tier Gateway is on.";
        };
        internalGatewayName = lib.mkOption {
          type = lib.types.str;
          default = "default-gateway";
          description = ''
            Name of the Gateway resource internal-tier HTTPRoutes
            attach to. Falls back to the public gateway when the
            internal tier is disabled, so misconfigurations degrade
            gracefully.
          '';
        };
        internalExposureMode = lib.mkOption {
          type = lib.types.str;
          default = "haproxy-local";
          description = "How the internal Gateway is reachable (haproxy-local | netbird | none).";
        };
        internalGatewayClusterIP = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Pinned ClusterIP for the traefik-internal Service (netbird mode).";
        };
        internalHostnames = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Registered internal-tier hostnames (deduped + sorted).";
        };
        internalDomain = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            DNS zone the internal tier is named under, or "" when there
            is no internal tier.

            Whatever resolves the internal tier claims this zone, so
            consumers read it here rather than deriving their own: netbird
            pushes exactly this to mesh peers, and CoreDNS answers it.
          '';
        };
      };
    };
  };

  config = lib.mkIf config.enable (
    let
      inherit (lib) optionals optionalAttrs;
      cidrLib = import ../../../lib/util/network.nix { inherit lib; };

      # k3s's ServiceLB binds 80 and 443 on the node, so a LoadBalancer
      # Service is reachable at the node's name. Nothing else does, and a
      # LoadBalancer there stays Pending forever with port 80 of the node
      # answering nothing.
      reachedByNodePort = config.controller == "traefik" && !cluster.provisionerOut.publishesGatewayPorts;

      httpPort = if config.controller == "traefik" then 8000 else 80;
      httpsPort = if config.controller == "traefik" then 8443 else 443;

      passthroughPort = if config.controller == "traefik" then config.tls.passthrough.port else 443;

      standardListeners = [
        {
          name = "http";
          protocol = "HTTP";
          port = httpPort;
          allowedRoutes.namespaces.from = "All";
        }
      ]
      ++ optionals (config.tls.enable && config.tls.domain != "") [
        {
          name = "https";
          protocol = "HTTPS";
          port = httpsPort;
          allowedRoutes.namespaces.from = "All";
          tls = {
            mode = "Terminate";

            certificateRefs = [
              { name = "gateway-tls"; }
            ]
            ++ map (
              r: { name = r.name; } // lib.optionalAttrs (r.namespace != null) { namespace = r.namespace; }
            ) config.tls.extraCertificateRefs;
          };
        }
      ]
      ++ optionals config.tls.passthrough.enable [
        {
          name = "tls-passthrough";
          protocol = "TLS";
          port = passthroughPort;
          allowedRoutes.namespaces.from = "All";
          tls.mode = "Passthrough";
        }
      ];

      publicGateway = {
        "default-gateway" = {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = {
            name = config.gatewayName;
            namespace = config.namespace;
            labels."catallaxy.io/network-tier" = "public";
          };
          spec = {
            gatewayClassName = config.className;
            listeners = standardListeners;
          };
        };
      };

      internalGateway = optionalAttrs config.internal.enable {

        "internal-gateway" = {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = {
            name = config.internal.name;
            namespace = config.namespace;
            labels."catallaxy.io/network-tier" = "internal";
            annotations."catallaxy.io/exposure-mode" = config.internal.exposureMode;
          };
          spec = {
            gatewayClassName = config.className;
            listeners = standardListeners;
          };
        };
      };

      internalService =
        optionalAttrs
          (
            config.controller == "traefik"
            && config.internal.enable
            && config.internal.exposureMode == "netbird"
            && config.internal.clusterIPAddress != null
          )
          {

            "traefik-internal" = {
              apiVersion = "v1";
              kind = "Service";
              metadata = {
                name = "traefik-internal";
                namespace = config.namespace;
                labels = {
                  "app.kubernetes.io/managed-by" = "catallaxy";
                  "catallaxy.io/network-tier" = "internal";
                };
              };
              spec = {
                type = "ClusterIP";
                clusterIP = config.internal.clusterIPAddress;
                selector = {
                  "app.kubernetes.io/instance" = "traefik-${config.namespace}";
                  "app.kubernetes.io/name" = "traefik";
                };
                ports = [
                  {
                    name = "web";
                    port = 80;
                    targetPort = "web";
                    protocol = "TCP";
                  }
                ]
                ++ optionals (config.tls.enable && config.tls.domain != "") [
                  {
                    name = "websecure";
                    port = 443;
                    targetPort = "websecure";
                    protocol = "TCP";
                  }
                ]
                ++ optionals config.tls.passthrough.enable [
                  {
                    name = "passthrough";
                    port = config.tls.passthrough.port;
                    targetPort = "passthrough";
                    protocol = "TCP";
                  }
                ];
              };
            };
          };

      externalGatewayClass = optionalAttrs (config.controller != "traefik") {
        "gateway-class" = {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "GatewayClass";
          metadata.name = config.className;
          spec.controllerName = config.controllerName;
        };
      };

      traefikHelm = optionalAttrs (config.controller == "traefik") {
        traefik = {
          chart = config.chart;
          releaseName = "traefik";
          namespace = config.namespace;
          values = {

            providers.kubernetesGateway = {
              enabled = true;
              experimentalChannel = true;
            };

            gateway.enabled = false;

            ingressRoute.dashboard.enabled = false;

            additionalArguments = [
              "--entryPoints.websecure.transport.respondingTimeouts.idleTimeout=0s"
              "--entryPoints.websecure.transport.respondingTimeouts.writeTimeout=0s"
              "--serversTransport.forwardingTimeouts.idleConnTimeout=0s"
              "--serversTransport.forwardingTimeouts.responseHeaderTimeout=0s"
            ];
          }

          // optionalAttrs reachedByNodePort {
            service.type = "NodePort";
            ports.web.nodePort = config.nodePorts.http;
            ports.websecure.nodePort = config.nodePorts.https;
          }

          // optionalAttrs config.tls.passthrough.enable {
            ports.passthrough = {
              port = config.tls.passthrough.port;
              expose.default = true;
              exposedPort = config.tls.passthrough.port;
              protocol = "TCP";
            }
            // optionalAttrs reachedByNodePort { nodePort = config.nodePorts.passthrough; };
          };
        };
      };

      tlsResources = optionalAttrs (config.tls.enable && config.tls.domain != "") {
        "gateway-tls-cert" = {
          apiVersion = "cert-manager.io/v1";
          kind = "Certificate";
          metadata = {
            name = "gateway-tls";
            namespace = config.namespace;
          };
          spec = {
            secretName = "gateway-tls";
            issuerRef = {
              name = config.tls.issuerRef.name;
              kind = config.tls.issuerRef.kind;
            };
            dnsNames = [
              config.tls.domain
              "*.${config.tls.domain}"
            ]
            ++ lib.optionals (config.internal.enable && config.internal.domain != "") [
              config.internal.domain
              "*.${config.internal.domain}"
            ];
          };
        };

        "http-to-https-redirect" = {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "HTTPRoute";
          metadata = {
            name = "http-to-https-redirect";
            namespace = config.namespace;

            annotations."external-dns.alpha.kubernetes.io/controller" = "none";
          };
          spec = {
            parentRefs = [
              {
                name = config.gatewayName;
                namespace = config.namespace;
                sectionName = "http";
              }
            ];
            hostnames = [ "*.${config.tls.domain}" ];
            rules = [
              {
                filters = [
                  {
                    type = "RequestRedirect";
                    requestRedirect = {
                      scheme = "https";
                      statusCode = 301;
                    };
                  }
                ];
              }
            ];
          };
        };
      };
    in
    {

      drift.expected = lib.optionals (config.controller == "traefik") [
        {
          group = "gateway.networking.k8s.io";
          kinds = [
            "Gateway"
            "HTTPRoute"
          ];
          managedBy = [ "traefik" ];
          reason = "traefik defaults listener/backendRef fields on the Gateway and HTTPRoute objects it admits.";
        }
      ];

      # The one mistake a route can make that nothing else catches: a lab with
      # `tls.enable = false` exports the listener name "http", and a route
      # naming "https" attaches to a listener that is not there. It fails at
      # apply time with a message about a parent that does not exist, which is
      # a long way from the line that caused it.
      lint.route-listener-exists = {
        description = "Every HTTPRoute and TLSRoute attaches to a listener some Gateway declares";
        severity = "error";
        scope = "per-cluster";
        format = "json";
        command = builtins.readFile ./lint/route-listener-exists.sh;
      };

      exports = {
        routing = {
          publicReady = "gateway/public/ready";
          controllerReady = "gateway/controller/ready";
        };
        inherit (config) className gatewayName;
        namespace = config.namespace;
        defaultTier = lab.policy.exposure.defaultTier or "public";
        passthroughEnabled = config.tls.passthrough.enable;
        passthroughPort = config.tls.passthrough.port;

        terminatingListenerName =
          if (config.tls.enable && config.tls.domain != "") then "https" else "http";

        internalEnabled = config.internal.enable;
        internalGatewayName = if config.internal.enable then config.internal.name else config.gatewayName;
        internalExposureMode = config.internal.exposureMode;
        internalGatewayClusterIP = config.internal.clusterIPAddress;

        internalHostnames = lib.unique (lib.sort lib.lessThan config.internalHostnames);
        internalDomain = if config.internal.enable then config.internal.domain else "";
      };

      verify.gateways-programmed = {
        description = "Every Gateway was programmed, so something is actually listening";
        reject = [
          {
            apiVersion = "gateway.networking.k8s.io/v1";
            kind = "Gateway";
            metadata.namespace = config.namespace;
            ${verifyTypes.conditionIsNot { type = "Programmed"; }} = true;
          }
        ];
      };

      assertions = [

        {
          assertion =
            !(config.tls.enable && config.tls.domain != "") || (peers.cert-manager.issuance != null);
          message = "gateway tls.enable requires floes.cert-manager to be enabled (reconciles the wildcard Certificate CR).";
        }
        {
          assertion =
            !(config.internal.enable && config.internal.exposureMode == "netbird")
            || config.internal.clusterIPAddress != null;
          message = ''
            floes.gateway.internal.clusterIPAddress must be set
            when internal.exposureMode = "netbird". Pick an IP inside
            the cluster's service CIDR but outside the kube-allocated
            range (convention: `<cidr-base>.250`). Required so
            internal-tier hostnames have a mesh-reachable address.
          '';
        }

        {
          assertion =
            config.internal.clusterIPAddress == null
            || cidrLib.ipInCidr config.internal.clusterIPAddress cluster.network.serviceSubnet;
          message = ''
            floes.gateway.internal.clusterIPAddress
            (${toString config.internal.clusterIPAddress}) is not inside
            cluster.network.serviceSubnet
            (${cluster.network.serviceSubnet}). The apiserver
            will reject the Service create with `failed to allocate
            IP: not in valid range`. Update clusterIPAddress to fall
            within the service subnet.
          '';
        }
      ];

      network = {

        declared = true;

        serves.web = {

          port = 80;

          fromExternal = true;

        };

        serves.websecure = {

          port = 443;

          fromExternal = true;

        };

      };

      imagesComplete = true;

      images.traefik = {

        repository = "traefik";

        tag = "v3.3.6";

      };

      # http and https keep the cluster's defaults when the provisioner
      # publishes them, but the passthrough listener has no such convention:
      # its port is whatever the lab set, so it is answered here either way
      # rather than left to a default that is only right by coincidence.
      ingress =
        if reachedByNodePort then
          {
            httpPort = config.nodePorts.http;
            httpsPort = config.nodePorts.https;
            passthroughPort = config.nodePorts.passthrough;
          }
        else
          {
            inherit passthroughPort;
          };

      capabilities.provides.api-gateway = contracts.api-gateway.apiGateway.claim {
        routing = {
          publicReady = "gateway/public/ready";
          controllerReady = "gateway/controller/ready";
        };
        internalEnabled = config.internal.enable;
      };
      bundles.gateway.conflicts = [ "api-gateway" ];
      bundles.gateway.disableWith = "floes.gateway.enable = false";

      prerequisites.gateway-api-crds = {
        yamls = [ k8sSpecs.standaloneCrds.gateway-api ];
        provides = [ "gateway-api/crds/established" ] ++ contracts.gateway-api.crdKinds;
      };

      bundles.gateway-controller.owner = {
        bootstrap = "install-target";
        steady = "argocd";
      };
      bundles.gateway-controller.helmCharts = traefikHelm;
      bundles.gateway-controller.resources = externalGatewayClass;

      bundles.gateway-controller.requires = [
        "gateway-api/crds/established"
      ];
      bundles.gateway-controller.provides = [
        "gateway/controller/ready"
      ];
      bundles.gateway-controller.readyProbe = {
        kind = "condition";
        resource = "deployment/traefik";
        namespace = config.namespace;
        condition = "Available";
        timeout = "5m";
      };

      bundles.gateway.owner = {
        bootstrap = "install-target";
        steady = "argocd";
      };
      bundles.gateway.resources = publicGateway // internalGateway // internalService;
      bundles.gateway.requires = [
        "gateway/controller/ready"
      ];
      bundles.gateway.provides = [
        "gateway/public/ready"
        "api-gateway"
      ]
      ++ contracts.gateway-api.routeKinds;

      # An address is the right thing to wait for when something assigns one:
      # it is the difference between a Gateway the controller has accepted and
      # one traffic can actually arrive at. A Gateway fronted by a NodePort
      # never gets one, because there is no address to assign, so waiting for
      # it waits out the timeout on a gateway that has been serving the whole
      # time. `Programmed` is what remains true in both cases.
      bundles.gateway.readyProbe =
        if reachedByNodePort then
          {
            kind = "condition";
            resource = "gateway/${config.gatewayName}";
            namespace = config.namespace;
            condition = "Programmed";
            timeout = "10m";
          }
        else
          {
            kind = "jsonpath";
            resource = "gateway/${config.gatewayName}";
            namespace = config.namespace;
            jsonpath = "{.status.addresses[0].value}";

            timeout = "10m";
          };

      bundles.gateway-tls.owner = {
        bootstrap = "install-target";
        steady = "argocd";
      };
      bundles.gateway-tls.resources = tlsResources;

      bundles.gateway-tls.requires = [
        "gateway/public/ready"
      ];
      bundles.gateway-tls.provides = [
        "gateway/tls/ready"
      ];

      bundles.gateway-tls.readyProbe = {
        kind = "condition";
        resource = "certificate/gateway-tls";
        namespace = config.namespace;
        condition = "Ready";
        timeout = "15m";
      };
    }
  );
}
