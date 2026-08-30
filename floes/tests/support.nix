# The harness every floe isolation check runs through.
#
# A floe is checked alone, against stub providers, so a failure names the floe
# rather than whatever lab happened to render it. This is how the shipped set
# stayed honest against five labs — most floes were never in most of them.
{ lib, pkgs }:

let
  catallaxy = import ../../lib/floe-catallaxy { inherit lib pkgs; };
  inherit (catallaxy) floe sigs kinds;

  floeSet = import ../../floes;

  # A stub for every signature a floe might ask for, so a check supplies only
  # the floe under test. The values are shaped like real ones and are not
  # real: nothing here renders, and a check asserting on a stub's value is
  # asserting on this file.
  stubs = {
    cluster = {
      sig = sigs.KUBERNETES_CLUSTER;
      value = {
        name = "stub";
        version = "1.31";
        context = "k3d-stub";
        podSubnet = "10.244.0.0/16";
        serviceSubnet = "10.96.0.0/12";
      };
    };

    gatewayApi = {
      sig = sigs.GATEWAY_API;
      value = {
        version = "v1.2.1";
        crdKinds = [ "kind:gateway.networking.k8s.io/HTTPRoute" ];
      };
    };

    apiGateway = {
      sig = sigs.API_GATEWAY;
      value = {
        className = "stub";
        baseDomain = "stub.test";
        parentRef = {
          name = "stub-gateway";
          namespace = "kube-system";
          sectionName = "https";
        };
      };
    };

    webhook = {
      sig = sigs.X509_WEBHOOK;
      value = {
        namespace = "cert-manager";
        readyToken = "stub/webhook/ready";
        crdKinds = [ "cert-manager.io/Certificate" ];
      };
    };

    generation = {
      sig = sigs.SECRET_GENERATION;
      value = {
        namespace = "external-secrets";
        readyToken = "stub/generation/ready";
        crdKinds = [ "external-secrets.io/ExternalSecret" ];
        generatorApiVersion = "generators.external-secrets.io/v1alpha1";
      };
    };

    issuance = {
      sig = sigs.X509_ISSUANCE;
      value = {
        readyToken = "stub/issuer/ready";
        publicIssuer = false;
        issuerRef = {
          name = "stub-ca";
          kind = "ClusterIssuer";
        };
        caSecret = {
          name = "stub-ca-secret";
          key = "tls.crt";
          namespace = "cert-manager";
        };
      };
    };
  };

  mkStub =
    name:
    { sig, value }:
    floe.mkFloe {
      name = "stub-${name}";
      provides.it = sig;
      modules = [ { config.floe.provides.it = value; } ];
    };

  stubUnits = lib.mapAttrs' (
    n: s: lib.nameValuePair "stub-${n}" ((mkStub n s).instantiate { })
  ) stubs;
in
{
  inherit catallaxy stubs;

  # evalFloe :: { name; inputs ? { }; } -> { link; cluster; component; bundles; }
  #
  # Every stub is in the link whether the floe asks for it or not: an unused
  # provider is not an error, and listing per-floe which stubs it needs would
  # be restating its `requires` in a second place that can disagree.
  evalFloe =
    {
      name,
      inputs ? { },
    }:
    let
      def = import floeSet.cluster.${name} {
        inherit
          lib
          pkgs
          floe
          sigs
          kinds
          ;
      };

      # A stub providing what the floe under test provides would be a second
      # provider, and the linker is right to refuse that — so the stub for a
      # signature this floe answers is dropped rather than the check being
      # written to expect a failure.
      provided = map (p: p.name) (lib.attrValues def.provides);
      usable = lib.filterAttrs (_: u: !(lib.elem u.def.provides.it.name provided)) stubUnits;

      link = floe.link {
        units = usable // {
          ${name} = def.instantiate inputs;
        };
      };

      cluster = catallaxy.elaborateCluster {
        linkResult = link;
        # Enough of the table to keep a derived `kind:` edge from resolving
        # against nothing; a floe's own CRDs come from its own declarations.
        coreKinds = lib.genAttrs [
          "Deployment"
          "StatefulSet"
          "DaemonSet"
          "Service"
          "ConfigMap"
          "Secret"
          "Namespace"
          "ServiceAccount"
          "Job"
        ] (_: true);
      };
    in
    {
      inherit link cluster;
      component = link.out."catallaxy.component".${name};
      bundles = link.out."catallaxy.component".${name}.bundles;
      provides = link.provides.${name};
      waves = map (w: map (b: b.name) w) cluster.waves;
    };

  # `builtins.tryEval` catches a `throw`; it cannot catch a missing attribute,
  # which is why the linker throws rather than asserting.
  fails = expr: !(builtins.tryEval (builtins.deepSeq expr "evaluated")).success;
}
