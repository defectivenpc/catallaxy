# Traefik as the Gateway API implementation, providing API_GATEWAY.
#
# Two bundles, which is the point of bundles: the controller and the Gateway
# object have different readiness (a running Deployment is not a programmed
# Gateway) and a real order between them. Both are this floe's business and
# `needs` says so without entering any namespace another floe can see.
#
# A port of what the example labs exercise, not of the old floe's full option
# surface: no internal tier, no passthrough, no NodePort fallback. TLS is
# here — it was absent only while nothing provided an issuer.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "gateway";
  summary = "Traefik as the Gateway API implementation, and the cluster's one Gateway.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = ''
        Store path of the Traefik Helm chart, defaulted from the pin in
        this floe's `upstream.nix`. Override to run a fork or a mirror.

        A path and not the derivation: `instantiate` deep-forces its inputs
        to check them eagerly, and a derivation is a self-referential
        attrset, so passing one overflows the stack before the floe is ever
        linked. `defaultText` is what keeps the store hash out of the
        generated page.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "kube-system";
      description = ''
        Namespace the controller and the Gateway live in. Neither bundle
        creates it: `kube-system` is one the cluster ships with, and emitting
        a Namespace object for it would have the applier adopt it.
      '';
    };

    className = lib.mkOption {
      type = lib.types.str;
      default = "traefik";
      description = "GatewayClass the Gateway names. Traefik's chart installs it.";
    };

    gatewayName = lib.mkOption {
      type = lib.types.str;
      default = "default-gateway";
      description = "Name of the Gateway resource routes attach to.";
    };

    tlsEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Terminate TLS on the Gateway, signed by whatever provides
        X509_ISSUANCE. Off by default: a lab with no issuer in its link
        cannot serve https, and quietly rendering a listener with no
        certificate produces a Gateway that never programs.
      '';
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = ''
        TLS listener port. Traefik maps its `websecure` entrypoint to 8443 in
        the pod and exposes it on 443, so the listener names the pod's port.
      '';
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = ''
        Listener port. Traefik's chart maps its `web` entrypoint to 8000 in
        the pod and exposes it on 80, so the listener has to name the pod's
        port and not the service's.
      '';
    };
  };

  # The domain routes through this gateway hang off. Every lab passed
  # `config.lab.dns.zone` here and the gateway then re-published it as
  # `API_GATEWAY.baseDomain` for its consumers, so the value made a round trip
  # through an input that could only ever hold one answer.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.zone = sigs.DNS_ZONE;

  # The Gateway and GatewayClass objects below have no types without these.
  # Resolved from a peer rather than installed here, because cilium's floe
  # needs the same CRDs and two installs of one thing is the conflict the
  # cluster used to route around by owning the install itself.
  requires.gatewayApi = sigs.GATEWAY_API;

  # Exactly-one, not fan-in, because this is a dependency rather than a
  # collection: the Gateway's certificate is signed by it, and the listener
  # never programs until the issuer exists. An optional hole would have made it
  # optional at the cost of the ordering edge, and core has no
  # optional-exactly-one hole — so every cluster with a gateway has an issuer,
  # and `tlsEnable` decides only whether it is used.
  requires.issuance = sigs.X509_ISSUANCE;

  # No fan-in. A hostname list on this floe's own options — which eight consumers used
  # to write *into* this floe — was inverted correctly, but the inversion is
  # `provides.gateway` below, not a collection.
  #
  # A consumer requires API_GATEWAY, gets `parentRef`, and renders its own
  # HTTPRoute with `kinds.mkRoute`. That is how Kubernetes already works: a
  # registered CRD is a primitive anyone may use. What this floe keeps is the
  # part only it can do — knowing what a well-formed route looks like, and
  # refusing an out-of-zone one at construction.
  provides.gateway = sigs.API_GATEWAY;

  # Every hostname the workloads behind this gateway publish, gathered here
  # because this is the thing that owns the hostname namespace — a route
  # attaches to it, and `policies.promisedHostsAreRouted` already identified a
  # gateway as the authority by scraping URLs out of its peers' provides.
  #
  # One contribution per unit, so a cluster's exposure is the fan-in and not a
  # list anyone maintains. The cluster exports it for a lab that fronts this
  # cluster and withholds it for one that does not. ADR 0004.
  collects.route = sigs.ROUTE_CLAIM;
  provides.exposure = sigs.HOST_EXPOSURE;

  # Where this cluster is dialled, which only the thing that created it knows.
  # Carried through rather than derived: the hostnames and the address have to
  # travel together for a route to mean anything, and this is where the
  # hostnames already are.
  #
  # Optional because a cluster nobody here created answers none, and that is
  # not a failure until a lab asks to front it — which the ingress says,
  # naming the cluster, rather than this floe refusing to be in one.
  optional.edge = sigs.CLUSTER_EDGE;

  out.component = kinds.component;
  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        zone = config.floe.requires.zone;

        issuance = config.floe.requires.issuance;
        tls = inputs.tlsEnable;

        claimed = lib.unique (map (c: c.host) (lib.attrValues config.floe.collects.route));

        reachedByNodePort = !config.floe.requires.cluster.assignsLoadBalancers;

        nodePorts = kinds.gatewayNodePorts;

        listenerName = if tls then "https" else "http";

        certSecret = "gateway-tls";
      in
      {
        options.gatewayResource = lib.mkOption {
          type = lib.types.attrs;
          description = "The Gateway object, and the single source of truth for what it is called.";
        };

        config.gatewayResource = {
          apiVersion = "gateway.networking.k8s.io/v1";
          kind = "Gateway";
          metadata = {
            name = inputs.gatewayName;
            namespace = inputs.namespace;
            labels."catallaxy.io/network-tier" = "public";

            labels."catallaxy.io/base-domain" = zone.zone;
          };
          spec = {
            gatewayClassName = inputs.className;
            listeners = [
              {
                name = "http";
                protocol = "HTTP";
                port = inputs.httpPort;
                allowedRoutes.namespaces.from = "All";
              }
            ]
            ++ lib.optional tls {
              name = "https";
              protocol = "HTTPS";
              port = inputs.httpsPort;
              allowedRoutes.namespaces.from = "All";
              tls = {
                mode = "Terminate";
                certificateRefs = [ { name = certSecret; } ];
              };
            };
          };
        };

        config.floe.provides.exposure = {
          hosts = claimed;
          edge = config.floe.requires.edge;
        };

        config.floe.provides.gateway = {
          className = config.gatewayResource.spec.gatewayClassName;
          baseDomain = zone.zone;
          parentRef = {
            inherit (config.gatewayResource.metadata) name namespace;
            sectionName = listenerName;
          };
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          assertions = [ ];

          backs.gateway = [
            "controller"
            "gateway"
          ];

          bundles = {
            controller = kinds.mkBundle {
              helmCharts.traefik = kinds.mkHelmChart {
                inherit (inputs) chart namespace;
                releaseName = "traefik";
                values = {
                  providers.kubernetesGateway = {
                    enabled = true;
                    experimentalChannel = true;
                  };

                  gateway.enabled = false;

                  ingressRoute.dashboard.enabled = false;
                }
                // lib.optionalAttrs reachedByNodePort {
                  service.type = "NodePort";
                  ports.web.nodePort = nodePorts.http;
                  ports.websecure.nodePort = nodePorts.https;
                }
                // {

                  additionalArguments = [
                    "--entryPoints.websecure.transport.respondingTimeouts.idleTimeout=0s"
                    "--entryPoints.websecure.transport.respondingTimeouts.writeTimeout=0s"
                    "--serversTransport.forwardingTimeouts.idleConnTimeout=0s"
                    "--serversTransport.forwardingTimeouts.responseHeaderTimeout=0s"
                  ];
                };
              };

              images.traefik = kinds.mkImage "docker.io/traefik:v3.3.6";

              ready = kinds.readyDeployment {
                name = "traefik";
                namespace = inputs.namespace;
              };

              ops.gateway.listeners = kinds.mkOpsCommand {
                description = "Show every listener the Gateway declares and its programmed status";
                command = [
                  "kubectl"
                  "-n"
                  inputs.namespace
                  "get"
                  "gateway"
                  inputs.gatewayName
                  "-o"
                  "jsonpath={range .status.listeners[*]}{.name}{\"\\t\"}{.attachedRoutes}{\"\\n\"}{end}"
                ];
              };
            };

            gateway = kinds.mkBundle {
              needs = [ "controller" ];

              resources = {
                default-gateway = config.gatewayResource;
              }
              // lib.optionalAttrs tls {
                gateway-tls = {
                  apiVersion = "cert-manager.io/v1";
                  kind = "Certificate";
                  metadata = {
                    name = certSecret;
                    namespace = inputs.namespace;
                  };
                  spec = {
                    secretName = certSecret;
                    dnsNames = [
                      zone.zone
                      "*.${zone.zone}"
                    ];
                    inherit (issuance) issuerRef;
                  };
                };
              };

              ready =
                if reachedByNodePort then
                  {
                    kind = "condition";
                    resource = "gateway/${inputs.gatewayName}";
                    namespace = inputs.namespace;
                    condition = "Programmed";
                    timeout = "10m";
                  }
                else
                  {
                    kind = "jsonpath";
                    resource = "gateway/${inputs.gatewayName}";
                    namespace = inputs.namespace;
                    jsonpath = "{.status.addresses[0].value}";
                    timeout = "10m";
                  };

              lint.route-listener-exists = {
                description = "Every HTTPRoute and TLSRoute attaches to a listener some Gateway declares";
                severity = "error";
                scope = "per-cluster";
                format = "json";
                command = builtins.readFile ./lint/route-listener-exists.sh;
              };

              lint.route-hostname-in-zone = {
                description = "Every route asks for a hostname some Gateway in this cluster can serve";
                severity = "error";
                scope = "per-cluster";
                format = "json";
                command = builtins.readFile ./lint/route-hostname-in-zone.sh;
              };

              verify.gateways-programmed = {
                description = "Every Gateway was programmed, so something is actually listening";
                timeout = "2m";
                expect = null;
                reject = [
                  {
                    apiVersion = "gateway.networking.k8s.io/v1";
                    kind = "Gateway";
                    metadata.namespace = inputs.namespace;
                    ${kinds.conditionIsNot { type = "Programmed"; }} = true;
                  }
                ];
              };
            };
          };
        };
      }
    )
  ];
}
