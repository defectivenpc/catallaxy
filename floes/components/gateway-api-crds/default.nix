# The Gateway API CRDs, as their own unit.
#
# These were once owned by the cluster rather than a floe: a
# mechanism that exists because gateway and cilium both install these, and a
# bundle declared by two floes is a conflicting definition. Here it is an
# ordinary floe providing GATEWAY_API, and the linker's exactly-one rule is
# what makes a second provider an error instead of a silent merge.
{
  lib,
  floe,
  upstream ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "gateway-api-crds";
  summary = "The Gateway API CRDs, so Gateway and route kinds have types.";

  inputs = {
    manifest = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.crds}";
      defaultText = lib.literalExpression "upstream.crds";
      description = ''
        Store path of the upstream CRD bundle. Required — the caller pins the
        URL and hash in `lib/k8s-specs.nix`.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = upstream.version;
      defaultText = lib.literalExpression "upstream.version";
      description = ''
        Gateway API release the manifest came from, defaulted from the same
        pin the manifest is fetched with, so the two cannot disagree.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.gatewayApi = sigs.GATEWAY_API;

  out.component = kinds.component;
  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;

        infraKinds = [
          "kind:gateway.networking.k8s.io/GatewayClass"
          "kind:gateway.networking.k8s.io/Gateway"
          "kind:gateway.networking.k8s.io/ReferenceGrant"
        ];

        routeKinds = [
          "kind:gateway.networking.k8s.io/HTTPRoute"
          "kind:gateway.networking.k8s.io/GRPCRoute"
          "kind:gateway.networking.k8s.io/TCPRoute"
          "kind:gateway.networking.k8s.io/TLSRoute"
          "kind:gateway.networking.k8s.io/UDPRoute"
          "kind:gateway.networking.k8s.io/BackendTLSPolicy"
          "kind:gateway.networking.k8s.io/BackendLBPolicy"
        ];
      in
      {
        config.floe.provides.gatewayApi = {
          inherit (inputs) version;
          crdKinds = infraKinds ++ routeKinds;
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          backs.gatewayApi = [ "crds" ];

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.manifest ];

            crds = map (lib.removePrefix "kind:") (infraKinds ++ routeKinds);
          };
        };
      }
    )
  ];
}
