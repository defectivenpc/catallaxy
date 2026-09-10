# forgejo, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  evalWith =
    {
      inputs ? { },
      without ? [ ],
    }:
    support.evalFloe {
      name = "forgejo";
      inputs = {
        chart = "/dev/null";
      }
      // inputs;
      inherit without;
    };
  r = evalWith { inputs.oidc = true; };
  values = r.bundles.forgejo.helmCharts.forgejo.values;
in
lib.runTests {

  # Two URLs because they are read by different things and only one resolves
  # in each place. A CD tool in the cluster clones over the Service; a human
  # needs the routed one. An earlier design had a single `gitRepo` and consumers
  # picked whichever happened to work where they were tested.
  testItPublishesBothUrls = {
    expr = {
      inherit (r.provides.git) internalUrl externalUrl;
    };
    expected = {
      internalUrl = "http://forgejo-http.forgejo.svc.cluster.local:3000";
      externalUrl = "https://git.stub.test";
    };
  };

  # Which keys, not just which Secret — the same reason OCI_REGISTRY carries
  # them.
  testItPublishesItsCredentials = {
    expr = r.provides.git.credentials;
    expected = {
      name = "forgejo-admin";
      namespace = "forgejo";
      # The username itself as well as the key holding it. What pushes needs
      # it as a literal — it goes into a URL, not a Secret lookup — and
      # passing the key name there authenticated as a user called "username".
      username = "forgejo-admin";
      usernameKey = "username";
      passwordKey = "password";
    };
  };

  # Left to the chart, the admin password is a literal in the rendered
  # manifest — the same render-time minting harbor's six had.
  testTheAdminPasswordIsMintedInCluster = {
    expr = {
      existing = values.gitea.admin.existingSecret;
      declared = r.bundles.forgejo.secrets;
    };
    expected = {
      existing = "forgejo-admin";
      declared = [ "forgejo/forgejo-admin" ];
    };
  };

  # Forgejo reserves `admin` and refuses to create it, failing the chart's
  # init job with a message about a reserved username rather than about the
  # value that was set. The username travels beside the password as
  # `extraData`, because a consumer cloning from here needs both and a
  # username is not a secret.
  testTheAdminUsernameTravelsWithThePassword = {
    expr = r.bundles.forgejo.resources.forgejo-admin-external-secret.spec.target.template.data.username;
    expected = "forgejo-admin";
  };

  # A lab this size runs one pod against SQLite. The chart's defaults bring up
  # an HA PostgreSQL and a six-node Redis cluster to serve it, and
  # `redis-cluster` is the one that is on unless turned off.
  testItRunsNoSupportingCluster = {
    expr = {
      pgHa = values."postgresql-ha".enabled;
      pg = values.postgresql.enabled;
      redis = values."redis-cluster".enabled;
      db = values.gitea.config.database.DB_TYPE;
    };
    expected = {
      pgHa = false;
      pg = false;
      redis = false;
      db = "sqlite3";
    };
  };

  # The chart defaults this from `ROOT_URL`, which would have the server bind
  # 443 in the pod and fail for want of a certificate — the certificate is on
  # the gateway.
  testItBindsThePodPortNotTheRoutedOne = {
    expr = values.gitea.config.server.HTTP_PORT;
    expected = 3000;
  };

  testItRegistersItsOwnClient = {
    expr = r.bundles.forgejo.resources.oauth2-client.spec.redirectUrl;
    expected = [ "https://git.stub.test/user/oauth2/kanidm/callback" ];
  };

  testTheClientSecretIsExternal = {
    expr = r.bundles.forgejo.externalSecrets;
    expected = [ "forgejo/forgejo-kanidm-oauth2-credentials" ];
  };

  testAskingWithNoIssuerIsRefused = {
    expr =
      support.fails
        (evalWith {
          inputs.oidc = true;
          without = [ "oidcProvider" ];
        }).bundles;
    expected = true;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };
}
