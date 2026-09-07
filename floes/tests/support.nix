# The harness every floe isolation check runs through.
#
# A floe is checked alone, against stub providers, so a failure names the floe
# rather than whatever lab happened to render it. This is how the shipped set
# stayed honest against five labs — most floes were never in most of them.
{ lib, pkgs }:

let
  catallaxy = import ../../lib/floe-catallaxy { inherit lib pkgs; };
  inherit (catallaxy) floe sigs kinds;

  # Flattened across `cluster` and `provisioners`, the same way `lib/lab.nix`
  # flattens it: the split is how the set is organised on disk, not a
  # namespace anything has to spell. A suite naming a provisioner floe would
  # otherwise be told the floe does not exist.
  floeSet = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../../floes));

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

        # The k3d answer, because that is what the stub's context says it is.
        # A floe whose rendering turns on this — the gateway is the one — has
        # its own suite covering both sides rather than relying on the stub.
        assignsLoadBalancers = true;
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
        crdKinds = [ "cert-manager.io/Certificate" ];
      };
    };

    objectStore = {
      sig = sigs.OBJECT_STORE;
      value = {
        namespace = "stub-store";
        s3Endpoint = "http://stub-s3.stub-store.svc.cluster.local:8333";
        credentials = null;
      };
    };

    generation = {
      sig = sigs.SECRET_GENERATION;
      value = {
        namespace = "external-secrets";
        crdKinds = [ "external-secrets.io/ExternalSecret" ];
        generatorApiVersion = "generators.external-secrets.io/v1alpha1";
      };
    };

    issuance = {
      sig = sigs.X509_ISSUANCE;
      value = {
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

    gitRepository = {
      sig = sigs.GIT_REPOSITORY;
      value = {
        internalUrl = "http://forgejo-http.forgejo.svc.cluster.local:3000";
        externalUrl = "https://git.stub.test";
        cloneUrl = "https://git.stub.test/stub-admin/lab.git";
        credentials = {
          name = "forgejo-admin";
          namespace = "forgejo";
          username = "stub-admin";
          usernameKey = "username";
          passwordKey = "password";
        };
      };
    };

    oidcProvider = {
      sig = sigs.OIDC_PROVIDER;
      value = {
        issuer = "https://idm.stub.test";
        authorizationEndpoint = "https://idm.stub.test/ui/oauth2";
        tokenEndpoint = "https://idm.stub.test/oauth2/token";
        clientCrd = "kaniop.rs/KanidmOAuth2Client";
        ref = {
          name = "stub-kanidm";
          namespace = "kanidm";
        };
        clientsAnyNamespace = true;
      };
    };

    trust = {
      sig = sigs.TRUST_BUNDLE;
      value = {
        namespace = "cert-manager";
        secretTargets = true;
        caBundle = {
          name = "lab-ca-bundle";
          key = "ca.crt";
        };
        caBundleSecret = {
          name = "lab-ca-bundle-secret";
          key = "ca.crt";
        };
      };
    };

    # Provided by the lab rather than by anything in a cluster, which is why
    # the isolation harness has to stand in for it like any other peer.
    zone = {
      sig = sigs.DNS_ZONE;
      value = {
        zone = "stub.test";
        server = "172.20.0.1";
        port = 5354;
      };
    };

    # The control plane, as a peer sees it. `managementInternalUrl` is here
    # and `T.local`, so a floe reading it in isolation succeeds and the same
    # floe reading it across a lab scope throws — which is why a check that
    # cares has to assert on which one was used, not merely that one was.
    mesh = {
      sig = sigs.MESH_NETWORK;
      value = {
        namespace = "netbird";
        managementUrl = "https://netbird.stub.test";
        managementInternalUrl = "http://netbird-management.netbird.svc.cluster.local:80";
        dashboardUrl = "https://netbird.stub.test";
      };
    };

    meshAdmin = {
      sig = sigs.MESH_ADMIN;
      value.tokenSecret = {
        namespace = "netbird";
        name = "netbird-api-token";
        key = "token";
      };
    };

    identityOperator = {
      sig = sigs.IDENTITY_OPERATOR;
      value = {
        crdsEstablished = "stub/kaniop/crds";
      };
    };

    logIngest = {
      sig = sigs.LOG_INGEST;
      value = {
        pushUrl = "http://stub-loki:3100/loki/api/v1/push";
        queryUrl = "http://stub-loki:3100";
        otlpUrl = "http://stub-loki:3100/otlp";
      };
    };

    traceIngest = {
      sig = sigs.TRACE_INGEST;
      value = {
        queryUrl = "http://stub-tempo:3100";
        otlpGrpc = "stub-tempo:4317";
        otlpHttp = "http://stub-tempo:4318";
      };
    };

    metricsIngest = {
      sig = sigs.METRICS_INGEST;
      value = {
        crdsEstablished = "stub/metrics/crds";
        crdKinds = [ "kind:monitoring.coreos.com/ServiceMonitor" ];
        queryUrl = "http://stub-prometheus:9090";
        remoteWriteUrl = "http://stub-prometheus:9090/api/v1/write";
      };
    };
  };

  mkStub =
    name:
    { sig, value }:
    floe.mkFloe {
      name = "stub-${name}";
      summary = "Fixture floe for a test suite.";
      provides.it = sig;
      modules = [ { config.floe.provides.it = value; } ];
    };

  stubUnits = lib.mapAttrs' (
    n: s: lib.nameValuePair "stub-${n}" ((mkStub n s).instantiate { })
  ) stubs;
in
{
  inherit catallaxy stubs;

  # evalFloe :: { name; inputs ? { }; without ? [ ]; } -> { link; cluster; ... }
  #
  # Every stub is in the link whether the floe asks for it or not: an unused
  # provider is not an error, and listing per-floe which stubs it needs would
  # be restating its `requires` in a second place that can disagree.
  #
  # `without` names stubs to leave out, for the one thing that arrangement
  # cannot express: an optional hole resolving to nothing. That is the
  # whole behaviour of an optional dependency, and with every stub always
  # present it is the one case never exercised.
  #
  # `stubValues` overrides fields on a stub's value, for a floe that reads a
  # fact through a `requires` hole rather than an input — varying it is then
  # varying the *provider*, and a check that wants to see a malformed zone
  # refused has nowhere else to put it.
  evalFloe =
    {
      name,
      inputs ? { },
      without ? [ ],
      stubValues ? { },
    }:
    let
      def = import floeSet.${name} {
        inherit
          lib
          pkgs
          catallaxy
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

      theseStubs = lib.mapAttrs' (
        n: s:
        lib.nameValuePair "stub-${n}" (
          (mkStub n (s // { value = s.value // (stubValues.${n} or { }); })).instantiate { }
        )
      ) stubs;

      usable = lib.filterAttrs (
        n: u: !(lib.elem u.def.provides.it.name provided) && !(lib.elem n (map (w: "stub-${w}") without))
      ) theseStubs;

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
