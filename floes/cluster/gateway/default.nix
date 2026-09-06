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
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "gateway";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = ''
        Store path of the Traefik Helm chart. Required — the caller pins it
        in `lib/charts.nix` and interpolates it.

        A path and not the derivation: `instantiate` deep-forces its inputs
        to check them eagerly, and a derivation is a self-referential
        attrset, so passing one overflows the stack before the floe is ever
        linked.
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

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # The domain routes through this gateway hang off. Every lab passed
  # `config.lab.dns.zone` here and the gateway then re-published it as
  # `API_GATEWAY.baseDomain` for its consumers, so the value made a round trip
  # through an input that could only ever hold one answer.
  requires.zone = sigs.DNS_ZONE;

  # The Gateway and GatewayClass objects below have no types without these.
  # Resolved from a peer rather than installed here, because cilium's floe
  # needs the same CRDs and two installs of one thing is the conflict the
  # shipped tree routes around with `cluster.prerequisites`.
  requires.gatewayApi = sigs.GATEWAY_API;

  # Exactly-one, not fan-in, because this is a dependency rather than a
  # collection: the Gateway's certificate is signed by it, and the listener
  # never programs until the issuer exists. `requiresMany` would have made it
  # optional at the cost of the ordering edge, and floe-core has no
  # optional-exactly-one hole — so every cluster with a gateway has an issuer,
  # and `tlsEnable` decides only whether it is used.
  requires.issuance = sigs.X509_ISSUANCE;

  # No fan-in. `floes.gateway.internalHostnames` — which eight consumers used
  # to write *into* this floe — was inverted correctly, but the inversion is
  # `provides.gateway` below, not a collection.
  #
  # A consumer requires API_GATEWAY, gets `parentRef`, and renders its own
  # HTTPRoute with `kinds.mkRoute`. That is how Kubernetes already works: a
  # registered CRD is a primitive anyone may use. What this floe keeps is the
  # part only it can do — knowing what a well-formed route looks like, and
  # refusing an out-of-zone one at construction.
  provides.gateway = sigs.API_GATEWAY;
  out.component = kinds.component;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        zone = config.floe.requires.zone;

        # Exactly-one, expressed over a fan-in hole: a lab either has an
        # issuer in the link or it does not, and `tls.enable` says which the
        # gateway was configured for. Two issuers is the linker's problem;
        # disagreeing with the lab is this floe's.
        issuance = config.floe.requires.issuance;
        tls = inputs.tlsEnable;

        # The listener a route attaches to. With TLS on, plaintext exists only
        # to be redirected, so a consumer's `parentRef` has to name the https
        # one — which is why this is derived rather than fixed.
        listenerName = if tls then "https" else "http";

        certSecret = "gateway-tls";
      in
      {
        # The assembly point. `provides` and `out` are both projections of
        # this, so a consumer's parentRef cannot drift from the Gateway that
        # actually gets applied.
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

            # The zone this Gateway serves, as rendered metadata.
            #
            # Inert to Kubernetes and load-bearing for
            # `lint.route-hostname-in-zone`, which reads what was applied
            # rather than what a floe was configured with. Without it the
            # zone exists only in the lab's `DNS_ZONE` and the lint has
            # nothing to compare against — it would find no zones
            # and pass by having looked at nothing.
            #
            # Not `listener.hostname`, which would be the Gateway API way to
            # say it and would have the gateway enforce it at runtime: a
            # wildcard listener does not match the apex, and `mkRoute`
            # deliberately allows a route on the base domain itself.
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

        config.floe.provides.gateway = {
          className = config.gatewayResource.spec.gatewayClassName;
          baseDomain = zone.zone;
          parentRef = {
            inherit (config.gatewayResource.metadata) name namespace;
            sectionName = listenerName;
          };
        };

        config.floe.out.component = kinds.mkComponent {
          # The chart renders one workload and `images.traefik` below is it.
          imagesComplete = true;

          # The lab's edge: everything from outside arrives here, and it
          # reaches every workload with a route. `reaches` is left empty
          # because the backends are whatever attached a route, which is not
          # knowable from here — the routes name the gateway, not the reverse.
          network = {
            declared = true;
            serves.http = {
              port = inputs.httpPort;
              fromExternal = true;
            };
            serves.https = {
              port = inputs.httpsPort;
              fromExternal = true;
            };
          };

          # The out-of-zone check that used to live here, over the fan-in,
          # is now in two places that between them cover more: `mkRoute`
          # refuses one at construction, where the trace names the floe that
          # asked, and `lint.route-hostname-in-zone` reads what was actually
          # rendered, which holds for a hand-written route too.
          assertions = [ ];

          # Both bundles have to be ready before a consumer's route means
          # anything: a route attached to a Gateway whose controller is not
          # running is admitted and serves nothing. Naming them here is what
          # lets a consumer order against this floe without naming either.
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

                  # The chart can create its own Gateway. This floe creates
                  # one, so letting the chart do it too would put two objects
                  # with different names in front of the same controller.
                  gateway.enabled = false;

                  ingressRoute.dashboard.enabled = false;

                  additionalArguments = [
                    "--entryPoints.websecure.transport.respondingTimeouts.idleTimeout=0s"
                    "--entryPoints.websecure.transport.respondingTimeouts.writeTimeout=0s"
                    "--serversTransport.forwardingTimeouts.idleConnTimeout=0s"
                    "--serversTransport.forwardingTimeouts.responseHeaderTimeout=0s"
                  ];
                };
              };

              images.traefik = {
                registry = "docker.io";
                repository = "traefik";
                tag = "v3.3.6";
                digest = null;
              };

              ready = {
                kind = "condition";
                resource = "deployment/traefik";
                namespace = inputs.namespace;
                condition = "Available";
                timeout = "5m";
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
                # One wildcard for the zone, so every route through this
                # gateway is covered by one certificate rather than one each.
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

              # A Deployment being Available says the controller is up; it
              # says nothing about whether this Gateway got an address. That
              # is a second fact and so a second probe.
              ready = {
                kind = "jsonpath";
                resource = "gateway/${inputs.gatewayName}";
                namespace = inputs.namespace;
                jsonpath = "{.status.addresses[0].value}";
                timeout = "10m";
              };

              # A check about *other* floes' output would not belong on a
              # bundle. This one reads every route in the cluster against the
              # listeners this bundle declares, which is this bundle's claim.
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
