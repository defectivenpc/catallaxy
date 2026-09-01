# An app a lab declares inline, behind the gateway.
#
# The escape hatch: something to run that has no floe of its own and does not
# need one. It takes resources, an optional chart, and puts a route in front.
#
# One app per instance, not an attrset of them. A `provides` is one value per
# hole, so a floe holding N apps cannot answer `ROUTE_REQUEST` N times — and
# the linker's exactly-one rule is what makes a route attach to exactly one
# gateway. The parked floe held the attrset and wrote every hostname into
# `floes.gateway.internalHostnames`, which is the sibling write RFC 0001
# removed. A lab with three apps instantiates this three times:
#
#     floes.hello   = floes.custom { name = "hello";   ... };
#     floes.welcome = floes.custom { name = "welcome"; ... };
#
# Always routed. Every app the parked labs declared through this set a
# gateway, which is what it is for; something that runs unexposed is a
# different thing and should say so by being a different floe.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "custom";

  inputs = {
    name = lib.mkOption {
      type = lib.types.str;
      description = ''
        What the app is called. Required.

        Used for the route, the bundle and the default hostname, so it is the
        one name a deployer has to pick rather than a name derived from a
        namespace that might hold several things.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      description = "Namespace it installs into. The floe creates this. Required.";
    };

    oidc = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register an OAuth2 client for this app with the lab's issuer.

        The client resource lands in this app's own namespace and the operator
        writes its credentials to `<name>-kanidm-oauth2-credentials` beside
        it — the operator's own naming, which nothing can override. What the app does
        with them is the app's business: this floe renders no configuration,
        because a `custom` app's config is whatever its `resources` say.
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalExpression "\"<name>.<the gateway's baseDomain>\"";
      description = ''
        Hostname the route answers on. Null derives it from the gateway's own
        `baseDomain`, which is where it should come from — a lab that spells
        its zone here has two places to change it.
      '';
    };

    serviceName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalExpression "the app's name";
      description = "Service the route sends to. Defaults to the app's name.";
    };

    servicePort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Port on that Service.";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "/";
      description = ''
        Path prefix the route matches.

        It reaches `exposedHosts`, so `cata lab verify` probes this rather
        than `/` — probing a path the route does not match proves nothing, and
        the gateway is right to refuse it.
      '';
    };

    resources = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Kubernetes resources, keyed by a name local to this app.";
    };

    yamls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Store paths of YAML files to apply as-is.";
    };

    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      example = lib.literalExpression ''
        { app = { registry = "ghcr.io"; repository = "me/app"; tag = "v1"; digest = null; }; }
      '';
      description = ''
        The images these resources pull.

        Not derived from the resources, deliberately. This floe cannot know
        whether what it was handed is the whole set — a chart it was given
        renders images nobody here can see — so `imagesComplete` is false and
        this is what an operator mirroring the lab gets. Declare them and the
        completeness gate has something to check.
      '';
    };

    ready = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = ''
        Readiness probe for the app, in the shape `lib/util/wait.nix` takes.
        Null waits only for the rollout of whatever workloads it rendered.
      '';
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.gateway = sigs.API_GATEWAY;

  # Optional, because most apps do not log anyone in and a lab may have no
  # issuer at all. `oidc = true` with nothing providing one is refused below
  # rather than rendering a client resource of an unknown kind.
  requiresOptional.oidc = sigs.OIDC_PROVIDER;

  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        gateway = config.floe.requires.gateway;

        service = if inputs.serviceName == null then inputs.name else inputs.serviceName;
        host = if inputs.hostname != null then inputs.hostname else "${inputs.name}.${gateway.baseDomain}";

        oidc = config.floe.requires.oidc or null;

        # The provider's own constructor. It returns the resource to render
        # and the reference to read the credentials back from — the operator
        # writes the Secret once it has reconciled the client, so the value
        # never exists at eval and never reaches a manifest.
        client =
          if inputs.oidc && oidc == null then
            # Not silently skipped. A lab that asks for a client and gets none
            # has an app whose login is simply off, with nothing anywhere
            # saying why — and the app is usually the last place anyone looks.
            throw ''
              app '${inputs.name}' asks for an OAuth2 client, and nothing in
              this cluster provides OIDC_PROVIDER.

              Add an issuer to the cluster, or set `oidc = false`.
            ''
          else
            lib.optionalAttrs inputs.oidc (
              kinds.mkOAuth2Client {
                provider = oidc;
                name = inputs.name;
                inherit (inputs) namespace;
                origin = "https://${host}";
              }
            );
      in
      {

        config.floe.out.component = kinds.mkComponent {
          # It cannot know. Whatever it was handed may pull images it has no
          # way to enumerate, and claiming otherwise would put a false claim
          # in front of the one gate that checks them.
          imagesComplete = false;

          network = {
            declared = true;
            serves.http.port = inputs.servicePort;
          };

          bundles.${inputs.name} = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];
            inherit (inputs) yamls images ready;

            resources =
              inputs.resources
              // lib.optionalAttrs (client != { }) { oauth2-client = client.resource; }
              // {
                # The gateway's own constructor. It takes `parentRef` off the
                # sealed value, so this floe never spells the gateway's name,
                # its namespace or its listener — and it refuses a hostname
                # outside the zone at construction, naming this floe.
                route = kinds.mkRoute {
                  inherit gateway service;
                  name = inputs.name;
                  inherit (inputs) namespace path;
                  hostname = host;
                  port = inputs.servicePort;
                };
              };
          };
        };
      }
    )
  ];
}
