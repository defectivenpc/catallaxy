# The Gateway API CRDs, as their own unit.
#
# In the shipped tree this is `cluster.prerequisites.gateway-api-crds`: a
# mechanism that exists because gateway and cilium both install these, and a
# bundle declared by two floes is a conflicting definition. Here it is an
# ordinary floe providing GATEWAY_API, and the linker's exactly-one rule is
# what makes a second provider an error instead of a silent merge.
{
  lib,
  floe,
  sigs,
  kinds,
}:

floe.mkFloe {
  name = "gateway-api-crds";

  inputs = {
    manifest = lib.mkOption {
      type = lib.types.str;
      description = ''
        Store path of the upstream CRD bundle. Required — the caller pins the
        URL and hash in `lib/k8s-specs.nix`.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      description = "Gateway API release the manifest came from. Required.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.api = sigs.GATEWAY_API;
  out.component = kinds.component;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;

        # Attaching to a parent is what a route is for, so a route kind is
        # only half-answered by the CRD existing; the gateway that admits one
        # answers the rest. These say the type exists.
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
        config.floe.provides.api = {
          inherit (inputs) version;
          crdKinds = infraKinds ++ routeKinds;
        };

        config.floe.out.component = kinds.mkComponent {
          backs.api = [ "crds" ];

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.manifest ];

            # `crdProviders` in manifest-autoedges reads CRDs out of
            # `resources`; these arrive as an upstream YAML file, which eval
            # cannot see inside, so the bundle says which kinds it installs.
            # Every consumer's `kind:` requirement resolves against this.
            crds = map (lib.removePrefix "kind:") (infraKinds ++ routeKinds);
          };
        };
      }
    )
  ];
}
