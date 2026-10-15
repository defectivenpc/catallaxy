# The harness every floe isolation check runs through.
#
# A floe is checked alone, against stub providers, so a failure names the floe
# rather than whatever lab happened to render it. This is how the shipped set
# stayed honest against five labs — most floes were never in most of them.
{
  lib,
  pkgs,
  floeCore,
}:

let
  catallaxy = import ../../lib/floe-catallaxy {
    inherit lib pkgs floeCore;
    crdTypes = (import ../crds.nix { inherit lib; }).types;
  };
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

        assignsLoadBalancers = true;
      };
    };

    storageClass = {
      sig = sigs.STORAGE_CLASS;
      value = {
        className = "stub";
        isDefault = true;
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

    provisioning = {
      sig = sigs.CLUSTER_PROVISIONING;
      value = {
        resourceKind = "clusters.example.com";
        resourceName = "stub-workload";
      };
    };

    secretStore = {
      sig = sigs.SECRET_STORE;
      value = {
        storeName = "catallaxy-runtime";
        storeKind = "ClusterSecretStore";

        writable = true;
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

    publication = {
      sig = sigs.PUBLISHED_SECRET;
      value = {
        storeName = "catallaxy-runtime";
        key = "stub/published/value";
        keys = [ ];
      };
    };

    zone = {
      sig = sigs.DNS_ZONE;
      value = {
        zone = "stub.test";
        server = "172.20.0.1";
        port = 5354;
      };
    };

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

    controlPlane = {
      sig = sigs.MANAGED_RESOURCE_CONTROL_PLANE;
      value = {
        namespace = "crossplane-system";
        providerKind = "pkg.crossplane.io/Provider";
      };
    };

    resourceProvider = {
      sig = sigs.MANAGED_RESOURCE_PROVIDER;
      value = {
        crdKinds = [ "nop.crossplane.io/NopResource" ];
        healthy = "stub/provider/healthy";
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

    labStore = {
      sig = sigs.LAB_SECRET_STORE;
      value = {
        name = "stub-labStore";

        writable = false;
        backend = "sops";
        writerCommand = null;
        removerCommand = null;
        vault = {
          server = null;
          path = "secret";
          version = "v2";
        };
      };
    };

    labSecret = {
      sig = sigs.LAB_SECRET;
      value = {
        name = "stub-labSecret";
        store = "stub-labStore";
        kind = "value";

        readableKeys = [ "token" ];
        keys.token = {
          generator = null;
          length = null;
        };
        hostPaths = { };
      };
    };

    labCa = {
      sig = sigs.LAB_CA;
      value = {
        pem = "{{STATE_DIR}}/proxy/lab.pem";
        caCert = "{{STATE_DIR}}/proxy/ca.crt";
        secret = {
          namespace = "cert-manager";
          name = "lab-ca-ca-secret";
        };
      };
    };

    resolver = {
      sig = sigs.HOST_RESOLVER;
      value = {
        container = "catallaxy-example-dns";
      };
    };

    network = {
      sig = sigs.LAB_NETWORK;
      value = {
        name = "example";
        subnet = "172.20.0.0/16";
        gateway = "172.20.0.1";
      };
    };

    ociMirror = {
      sig = sigs.OCI_MIRROR;
      value = {
        name = "stub-ociMirror";
        port = 5050;
      };
    };

    edge = {
      sig = sigs.CLUSTER_EDGE;
      value = {
        backend = "k3d-stub-server-0";
        httpPort = 80;
        httpsPort = 443;
      };
    };

    exposure = {
      sig = sigs.HOST_EXPOSURE;
      value = {
        hosts = [ "app.stub.test" ];
        edge = {
          backend = "k3d-stub-server-0";
          httpPort = 80;
          httpsPort = 443;
        };
      };
    };

    step = {
      sig = sigs.LAB_STEPS;
      value.steps.stub-step = {
        kind = "run-script";
        description = "Stub contributed step";
        beforeClusters = "created";
      };
    };

    service = {
      sig = sigs.HOST_SERVICE;
      value = {
        description = "Stub host service";
        container = "catallaxy-stub-thing";
        image = "stub:1";
        command = [ ];
        ports = [ "127.0.0.1:9999:80" ];
        networks = [ "stub" ];
        dnsContainers = [ ];
        volumes = { };
        extraMounts = [ ];
        readyProbe = null;
      };
    };

    delivery = {
      sig = sigs.DELIVERY_POLICY;
      value = {
        strategy = "kapp";
        bootstrapTool = "kubectl-ssa";
        waitTimeout = "5m";
        context = "k3d-stub";
      };
    };
  };

  # Named by the signature's `canonicalName` rather than `it`. Every stub
  # calling its provide `it` made one name mean eighteen signatures, which
  # `link` refuses — and rightly: the rule exists so that a reader seeing
  # `provides.<name>` can tell what it is.
  mkStub =
    name:
    { sig, value }:
    floe.mkFloe {
      name = "stub-${name}";
      summary = "Fixture floe for a test suite.";
      provides.${sig.canonicalName} = sig;
      modules = [ { config.floe.provides.${sig.canonicalName} = value; } ];
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
        cataCharts = null;
        k8sSpecs = null;
        inherit
          lib
          pkgs
          catallaxy
          floe
          sigs
          kinds
          ;
      };

      provided = map (p: p.name) (lib.attrValues def.provides);

      unknown = lib.subtractLists (lib.attrNames stubs) (without ++ lib.attrNames stubValues);

      refuse = lib.throwIf (unknown != [ ]) (
        "evalFloe '${name}': no stub named ${lib.concatMapStringsSep ", " (s: "'${s}'") unknown}. "
        + "`without` and `stubValues` name stubs by signature canonical name; "
        + "the set is ${lib.concatStringsSep ", " (lib.attrNames stubs)}."
      );

      theseStubs = refuse (
        lib.mapAttrs' (
          n: s:
          lib.nameValuePair "stub-${n}" (
            (mkStub n (s // { value = s.value // (stubValues.${n} or { }); })).instantiate { }
          )
        ) stubs
      );

      usable = lib.filterAttrs (
        n: u:
        !(lib.elem (lib.head (lib.attrValues u.def.provides)).name provided)
        && !(lib.elem n (map (w: "stub-${w}") without))
      ) theseStubs;

      link = floe.link {
        units = usable // {
          ${name} = def.instantiate inputs;
        };
        defaults = lib.mapAttrs' (
          n: u: lib.nameValuePair (lib.head (lib.attrValues u.def.provides)).name n
        ) usable;
      };

      cluster = catallaxy.elaborateCluster {
        linkResult = link;
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
      inherit link cluster def;
      component = link.out."catallaxy.component".${name};
      bundles = link.out."catallaxy.component".${name}.bundles;
      provides = link.provides.${name};
      waves = map (w: map (b: b.name) w) cluster.waves;
    };

  # `builtins.tryEval` catches a `throw`; it cannot catch a missing attribute,
  # which is why the linker throws rather than asserting.
  fails = expr: !(builtins.tryEval (builtins.deepSeq expr "evaluated")).success;
}
