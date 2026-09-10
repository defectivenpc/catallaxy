# netbird, alone.
#
# The floe with the most that can be quietly wrong: two credentials shared
# between workloads that fail apart rather than together, an OIDC client whose
# audience has to match in three places, and three hostnames that have to be
# inside the gateway's zone and agree with the certificate covering it.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "netbird";
  };

  server = r.bundles.server;
  creds = r.bundles.credentials;
  dash = r.bundles.dashboard;
  auto = r.bundles.automation;

  mgmt = server.resources.netbird-management;

  configTemplate =
    builtins.fromJSON
      server.resources.netbird-management-cm.data."management.tmpl.json";

  container = lib.head mgmt.spec.template.spec.containers;
  initContainer = lib.head mgmt.spec.template.spec.initContainers;

  dashEnv = lib.listToAttrs (
    map (
      e: lib.nameValuePair e.name e.value
    ) (lib.head dash.resources.netbird-dashboard.spec.template.spec.containers).env
  );

  relayEnv = lib.listToAttrs (
    map (
      e: lib.nameValuePair e.name (e.value or "«fromSecret»")
    ) (lib.head server.resources.netbird-relay.spec.template.spec.containers).env
  );

  hostnamesOf = route: route.spec.hostnames;
in
lib.runTests {

  # ---- the two credentials, and who reads them --------------------------

  # The relay validates what management issued, so both read one secret. They
  # do not fail together when it is wrong: management starts fine and every
  # relayed connection is refused, which reads as a network fault.
  testTheRelaySecretIsOneValueReadTwice = {
    expr = {
      relay = relayEnv.NB_AUTH_SECRET;
      inConfig = configTemplate.Relay.Secret;
      secretRef =
        (lib.findFirst (e: e.name == "NB_AUTH_SECRET") null (
          (lib.head server.resources.netbird-relay.spec.template.spec.containers).env
        )).valueFrom.secretKeyRef;
    };
    expected = {
      relay = "«fromSecret»";

      # A placeholder, not the value: the init container substitutes it. A
      # credential reaching the ConfigMap would reach the manifest, the digest
      # that pins it, and the Nix store.
      inConfig = "@RELAY_AUTH_SECRET@";
      secretRef = {
        name = "netbird-relay-auth";
        key = "secret";
      };
    };
  };

  testNeitherCredentialIsRenderedIntoTheConfig = {
    expr = {
      relay = configTemplate.Relay.Secret;
      datastore = configTemplate.DataStoreEncryptionKey;
    };
    expected = {
      relay = "@RELAY_AUTH_SECRET@";
      datastore = "@DATASTORE_ENC_KEY@";
    };
  };

  # Both are generated in-cluster, so both are ExternalSecrets rather than
  # Secrets, and the bundle declares what it causes to exist.
  testBothCredentialsAreMintedInCluster = {
    expr = lib.sort (a: b: a < b) creds.secrets;
    expected = [
      "netbird/netbird-datastore-key"
      "netbird/netbird-relay-auth"
    ];
  };

  # The servers wait on the credentials through the graph. Both are mounted by
  # `subPath`, and a pod whose subPath source is missing sits in
  # CreateContainerConfigError rather than retrying cleanly — which is a pod
  # that never recovers on its own.
  testTheServersWaitOnTheCredentials = {
    expr = server.needs;
    expected = [ "credentials" ];
  };

  # ---- the OIDC client --------------------------------------------------

  # Public, because the dashboard runs in a browser and cannot hold a secret.
  # kaniop writes no Secret for a public client, so anything reading one would
  # wait forever.
  testTheDashboardClientIsPublic = {
    expr = creds.resources.netbird-oauth2-client.spec.public or false;
    expected = true;
  };

  # The audience is checked in three places and they are one string: the
  # dashboard asks for a token with it, management validates it, and PKCE
  # requests it.
  testOneAudienceReachesAllThreeReaders = {
    expr = {
      dashboard = dashEnv.AUTH_AUDIENCE;
      management = configTemplate.HttpConfig.AuthAudience;
      pkce = configTemplate.PKCEAuthorizationFlow.ProviderConfig.Audience;
    };
    expected = {
      dashboard = "netbird";
      management = "netbird";
      pkce = "netbird";
    };
  };

  # The *client's* issuer, not the server's. A token minted for this client
  # carries `<issuer>/oauth2/openid/<client>`, and validating against the bare
  # issuer rejects every token with a mismatch naming neither.
  testTokensAreValidatedAgainstTheClientsIssuer = {
    expr = {
      authority = dashEnv.AUTH_AUTHORITY;
      issuer = configTemplate.HttpConfig.AuthIssuer;
      keys = configTemplate.HttpConfig.AuthKeysLocation;
    };
    expected = {
      authority = "https://idm.stub.test/oauth2/openid/netbird";
      issuer = "https://idm.stub.test/oauth2/openid/netbird";
      keys = "https://idm.stub.test/oauth2/openid/netbird/public_key.jwk";
    };
  };

  # Off the signature, not off kanidm by name. These two are account-level
  # rather than per-client, which is why they are fields on OIDC_PROVIDER and
  # not on what the client constructor returns.
  testTheOauthEndpointsComeFromTheSignature = {
    expr = {
      inherit (configTemplate.PKCEAuthorizationFlow.ProviderConfig)
        AuthorizationEndpoint
        TokenEndpoint
        ;
    };
    expected = {
      AuthorizationEndpoint = "https://idm.stub.test/ui/oauth2";
      TokenEndpoint = "https://idm.stub.test/oauth2/token";
    };
  };

  # ---- one hostname, five backends --------------------------------------

  # Derived from one input and the gateway's own zone, which is what makes it
  # servable: the wildcard certificate covers the zone and nothing else.
  testThereIsOneHostname = {
    expr = hostnamesOf server.resources.netbird-route;
    expected = [ "netbird.stub.test" ];
  };

  # The whole routing table, in order of what serves what. `/` is the
  # dashboard, which is the fix for the failure that found this design: an API
  # at the root answers 404, and 404 is what a gateway with *no* route answers,
  # so the lab's endpoint probe cannot tell them apart and refuses to try.
  testEveryPathReachesTheRightBackend = {
    expr = map (r: {
      path = (lib.head r.matches).path.value;
      backend = (lib.head r.backendRefs).name;
      port = (lib.head r.backendRefs).port;
    }) server.resources.netbird-route.spec.rules;
    expected = [
      {
        path = "/api";
        backend = "netbird-management";
        port = 80;
      }
      {
        path = "/management.ManagementService/";
        backend = "netbird-management";
        port = 80;
      }
      {
        path = "/signalexchange.SignalExchange/";
        backend = "netbird-signal";
        port = 80;
      }
      {
        path = "/relay";
        backend = "netbird-relay";
        port = 33080;
      }
      {
        path = "/";
        backend = "netbird-dashboard";
        port = 80;
      }
    ];
  };

  # The dashboard has no route of its own. Two HTTPRoutes for one hostname is
  # two sets of rules merged by specificity, which is a decision nobody wrote.
  testTheDashboardHasNoRouteOfItsOwn = {
    expr = lib.filter (n: lib.hasInfix "route" n) (lib.attrNames dash.resources);
    expected = [ ];
  };

  # A peer told `rels://<host>` with no path opens a websocket against the
  # dashboard, gets a 404, and reports the relay as unreachable.
  testTheRelayIsAdvertisedWithItsPath = {
    expr = {
      inConfig = configTemplate.Relay.Addresses;
      exposed = relayEnv.NB_EXPOSED_ADDRESS;
    };
    expected = {
      inConfig = [ "rels://netbird.stub.test/relay" ];
      exposed = "netbird.stub.test/relay";
    };
  };

  # The dashboard is a browser app, so both endpoints are the routed name and
  # not the Service: the Service resolves nowhere the visitor is.
  testTheDashboardDialsTheRoutedApi = {
    expr = {
      api = dashEnv.NETBIRD_MGMT_API_ENDPOINT;
      grpc = dashEnv.NETBIRD_MGMT_GRPC_API_ENDPOINT;
    };
    expected = {
      api = "https://netbird.stub.test";
      grpc = "https://netbird.stub.test";
    };
  };

  # Signal is reached by peers over TLS on 443 through the gateway, on the
  # same host as everything else — it is told apart by its gRPC path prefix,
  # not by a name of its own.
  testPeersAreToldTheRoutedSignalName = {
    expr = configTemplate.Signal;
    expected = {
      Proto = "https";
      URI = "netbird.stub.test:443";
      Username = "";
      Password = null;
    };
  };

  # ---- what a gRPC service has to say about itself ----------------------

  # The peer protocol is gRPC and the API is gRPC-Web. Without `h2c` on the
  # Service port the gateway negotiates HTTP/1.1 and a peer's registration
  # hangs with no error on either side.
  testTheGrpcPortsDeclareH2c = {
    expr = map (p: {
      inherit (p) name;
      appProtocol = p.appProtocol or null;
    }) server.resources.netbird-management-svc.spec.ports;
    expected = [
      {
        name = "http";
        appProtocol = "kubernetes.io/h2c";
      }
      {
        name = "grpc";
        appProtocol = "kubernetes.io/h2c";
      }
    ];
  };

  # ---- the store ---------------------------------------------------------

  # sqlite tolerates one writer and the volume is ReadWriteOnce, so a rolling
  # update that runs two pods at once deadlocks on the PVC.
  testTheStoreIsNotRolled = {
    expr = {
      strategy = mgmt.spec.strategy.type;
      replicas = mgmt.spec.replicas;
    };
    expected = {
      strategy = "Recreate";
      replicas = 1;
    };
  };

  # The rendered config holds both credentials in clear, so it lives in memory
  # and never on disk.
  testTheRenderedConfigNeverTouchesDisk = {
    expr =
      (lib.head (lib.filter (v: v.name == "config") mgmt.spec.template.spec.volumes)).emptyDir.medium;
    expected = "Memory";
  };

  # Nothing restarts a server when a mounted ConfigMap changes, and management
  # reads its config once at startup. This is what rolls it.
  testAConfigChangeRollsTheServer = {
    expr = mgmt.spec.template.metadata.annotations ? "catallaxy.io/config-hash";
    expected = true;
  };

  # ---- trust ---------------------------------------------------------------

  # The failure this exists for: management validates every token by fetching
  # the issuer's signing keys over HTTPS, and in a lab that issuer is served
  # from the lab's own CA. Without the bundle the fetch fails x509
  # verification and *every* login is refused, with an error about a
  # certificate from a component nobody was watching.
  #
  # `SSL_CERT_DIR` appends rather than replaces: netbird reaches public
  # addresses too, and a container told to trust only the lab CA stops
  # trusting everything else.
  testItTrustsTheLabCaWithoutLosingThePublicRoots = {
    expr = {
      certDir = (lib.findFirst (e: e.name == "SSL_CERT_DIR") null container.env).value;
      mounted = lib.any (m: m.mountPath == "/etc/netbird-ca") container.volumeMounts;
    };
    expected = {
      certDir = "/etc/ssl/certs:/etc/netbird-ca";
      mounted = true;
    };
  };

  # The ConfigMap and the key both come off TRUST_BUNDLE. trust-manager
  # decides what it calls them, and a floe that spelled `lab-ca-bundle` for
  # itself would break the day the distributor changed its mind.
  testTheBundleComesOffTheSignature = {
    expr = (lib.findFirst (v: v.name == "lab-ca") null mgmt.spec.template.spec.volumes).configMap;
    expected = {
      name = "lab-ca-bundle";
      items = [
        {
          key = "ca.crt";
          path = "lab-ca.crt";
        }
      ];
    };
  };

  # ---- the one credential nobody owns --------------------------------------

  # The identity is a CR, not a runbook step. kaniop mints the account and the
  # token and rotates it — which is the difference between a credential that
  # expires into an outage and one that expires into a reconcile.
  testTheMachineIdentityIsDeclaredAndRotated = {
    expr =
      let
        sa = auto.resources.netbird-service-account;
      in
      {
        inherit (sa) kind;
        rotation = sa.spec.apiTokenRotation.enabled;
        tokenSecret = (lib.head sa.spec.apiTokens).secretName;
        purpose = (lib.head sa.spec.apiTokens).purpose;
      };
    expected = {
      kind = "KanidmServiceAccount";
      rotation = true;
      tokenSecret = "netbird-kanidm-token";
      purpose = "readwrite";
    };
  };

  # Named apart from the OAuth2 client on purpose: kanidm has one name
  # namespace across every principal kind, and both being `netbird` produced a
  # 500 whose only honest reading was in kanidm's own log.
  # `kanidmPrincipalsAreUnique` refuses that at eval now.
  testTheAccountAndTheClientDoNotShareAName = {
    expr = {
      client = creds.resources.netbird-oauth2-client.metadata.name;
      account = auto.resources.netbird-service-account.metadata.name;
    };
    expected = {
      client = "netbird";
      account = "netbird-operator";
    };
  };

  # The token step waits on the *key*, not the object: kaniop creates the
  # Secret and issues the token in two round trips, so a consumer that waited
  # on the Secret alone would exchange an empty string.
  testTheTokenStepWaitsForTheTokenNotTheSecret = {
    expr = auto.ready;
    expected = {
      kind = "jsonpath";
      resource = "secret/netbird-kanidm-token";
      namespace = "netbird";
      jsonpath = "{.data.token}";
      timeout = "5m";
    };
  };

  # Neither Secret is in the manifest stream — one is written by kaniop, the
  # other by the Job — so both are declared as arriving from outside. Without
  # that the reference rule calls them dangling, which is true of the
  # manifests and false of the cluster.
  testWhatArrivesFromOutsideIsDeclared = {
    expr = lib.sort (a: b: a < b) auto.externalSecrets;
    expected = [
      "netbird/netbird-api-token"
      "netbird/netbird-kanidm-token"
    ];
  };

  # The heal is the same script on a schedule, not a second implementation of
  # the same idea. Two of those drift, and the one that runs hourly is the one
  # nobody reads.
  testTheHealRunsTheSameScriptAsTheBootstrap = {
    expr =
      let
        cron = auto.resources.netbird-pat-heal;
        cronSpec = cron.spec.jobTemplate.spec.template.spec;
        job = lib.head (lib.attrValues (lib.filterAttrs (_: r: (r.kind or "") == "Job") auto.resources));
      in
      {
        sameCommand =
          (lib.head cronSpec.containers).command == (lib.head job.spec.template.spec.containers).command;
        # A slow run against an unreachable management must not stack up
        # behind itself.
        concurrency = cron.spec.concurrencyPolicy;
      };
    expected = {
      sameCommand = true;
      concurrency = "Forbid";
    };
  };

  # It talks to management over the Service. The routed name would leave the
  # cluster and come back through the ingress to reach a pod one hop away —
  # which works until the ingress is the thing being replaced.
  testTheTokenStepDialsTheServiceNotTheIngress = {
    expr =
      let
        env = lib.listToAttrs (
          map (
            e: lib.nameValuePair e.name e.value
          ) (lib.head auto.resources.netbird-pat-heal.spec.jobTemplate.spec.template.spec.containers).env
        );
      in
      {
        url = env.NB_URL;
        ca = env.CA_FILE;
      };
    expected = {
      url = "http://netbird-management.netbird.svc.cluster.local:80";
      ca = "/etc/netbird-ca/lab-ca.crt";
    };
  };

  # Where the token landed, said once, by whoever chose the name. The operator
  # is `floes/cluster/netbird-operator` now and may be in another cluster
  # entirely; what stays here is minting the token and promising its address.
  testItPromisesWhereTheTokenLanded = {
    expr = r.provides.meshAdmin.tokenSecret;
    expected = {
      namespace = "netbird";
      name = "netbird-api-token";
      key = "token";
    };
  };

  # Ordering, stated once: the token step needs a running management to ask.
  # What waits on the step is whoever resolved MESH_ADMIN, through `backs`,
  # and that is a different floe.
  testTheChainIsOrderedByWhatItNeeds = {
    expr = auto.needs;
    expected = [ "server" ];
  };

  # ---- claims about itself ------------------------------------------------

  testItNamesEveryImageItRuns = {
    expr = {
      inherit (r.component) imagesComplete;
      images = lib.sort (a: b: a < b) (lib.attrNames r.cluster.images);
    };
    expected = {
      imagesComplete = true;
      images = [
        "netbird/automation/tools"
        "netbird/dashboard/dashboard"
        "netbird/server/management"
        "netbird/server/relay"
        "netbird/server/signal"
        "netbird/server/wait"
      ];
    };
  };

  # Two promises, two waits. A consumer resolving MESH_NETWORK waits for the
  # servers and not for the UI in front of them — the dashboard being down is
  # not the mesh being down — while one resolving MESH_ADMIN waits for the Job
  # that mints the token, which is a longer wait and only for whoever needs it.
  testEachPromiseWaitsForWhatStandsBehindIt = {
    expr = r.component.backs;
    expected = {
      mesh = [ "server" ];
      meshAdmin = [ "automation" ];
    };
  };

  # Two URLs for one server. An in-cluster consumer that used the routed one
  # would leave the cluster and come back through the ingress to reach a pod
  # one hop away — which works until the ingress is the thing being replaced.
  testItPublishesBothWaysToReachManagement = {
    expr = {
      inherit (r.provides.mesh) managementUrl managementInternalUrl;
    };
    expected = {
      managementUrl = "https://netbird.stub.test";
      managementInternalUrl = "http://netbird-management.netbird.svc.cluster.local:80";
    };
  };

  # The init container is the whole reason the credentials stay out of the
  # manifest, so what it mounts is worth pinning.
  testTheInitContainerHasBothCredentials = {
    expr = lib.sort (a: b: a < b) (
      map (m: m.subPath or m.name) (lib.filter (m: m ? subPath) initContainer.volumeMounts)
    );
    expected = [
      "key"
      "secret"
    ];
  };

  testTheServerRunsTheImageTheFloePinned = {
    expr = container.image;
    expected = "docker.io/netbirdio/management:0.60.2";
  };
}
