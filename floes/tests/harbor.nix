# harbor, alone.
#
# Mostly about the six secrets. Left to itself the chart mints them with
# `randAlphaNum` while rendering, so all six land in the manifest, in the
# digest that pins it, and in the store — and all six change on any re-render.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  evalWith =
    {
      inputs ? { },
      without ? [ ],
    }:
    support.evalFloe {
      name = "harbor";
      inputs = {
        chart = "/dev/null";
      }
      // inputs;
      inherit without;
    };

  r = evalWith { inputs.oidc = true; };
  values = r.bundles.harbor.helmCharts.harbor.values;

  # Every ExternalSecret this bundle renders, as `<secret> -> <length>`.
  generators = lib.mapAttrs (_: v: v.spec.data or v.spec) (
    lib.filterAttrs (_: v: (v.kind or "") == "Password") r.bundles.harbor.resources
  );
in
lib.runTests {

  # Seven, not six. The eighth — the token CA — is cert-manager's, so it is
  # an `externalSecrets` entry rather than one this bundle mints.
  #
  # Three carry a `-secret`/`-http-secret` suffix rather than reading as the
  # obvious name, and that is the fix for a real failure: the chart renders
  # its own `harbor-core`, `harbor-jobservice` and `harbor-registry`, and an
  # ExternalSecret targeting one takes it over and drops every key the chart
  # put there. `secret-ownership` in the CLI now refuses the collision; this
  # pins the names that avoid it.
  testEverySecretIsMintedInCluster = {
    expr = lib.sort (a: b: a < b) r.bundles.harbor.secrets;
    expected = [
      "harbor/harbor-admin"
      "harbor/harbor-core-secret"
      "harbor/harbor-jobservice-secret"
      "harbor/harbor-registry-credential"
      "harbor/harbor-registry-http-secret"
      "harbor/harbor-secret-key"
      "harbor/harbor-xsrf"
    ];
  };

  testTheTokenCaIsIssuedNotMinted = {
    expr = r.bundles.harbor.resources.harbor-token.spec.secretName;
    expected = "harbor-token-ca";
  };

  # The chart mints one for anything not pointed at an existing Secret, so a
  # missed `existingSecret` is a secret in the manifest.
  testTheChartMintsNone = {
    expr = {
      admin = values.existingSecretAdminPassword;
      secretKey = values.existingSecretSecretKey;
      core = values.core.existingSecret;
      xsrf = values.core.existingXsrfSecret;
      jobservice = values.jobservice.existingSecret;
      registry = values.registry.existingSecret;

      # These two were missed, and the chart minted both on every render: a
      # token-signing keypair via `genSelfSignedCert`, and an htpasswd whose
      # bcrypt salt is fresh each time. Both landed in the manifest and in the
      # digest, and both rotated on every apply.
      token = values.core.secretName;
      registryCred = values.registry.credentials.existingSecret;
    };
    expected = {
      admin = "harbor-admin";
      secretKey = "harbor-secret-key";
      core = "harbor-core-secret";
      xsrf = "harbor-xsrf";
      jobservice = "harbor-jobservice-secret";
      registry = "harbor-registry-http-secret";
      token = "harbor-token-ca";
      registryCred = "harbor-registry-credential";
    };
  };

  # The htpasswd is derived from the generated password inside the cluster,
  # so the salt never reaches a rendered file.
  testTheHtpasswdIsTemplatedNotRendered = {
    expr =
      r.bundles.harbor.resources."harbor-registry-credential-external-secret".spec.target.template.data.REGISTRY_HTPASSWD;
    expected = ''{{ htpasswd "harbor_registry_user" .password }}'';
  };

  # Harbor uses `secretKey` as an AES key and refuses to start on anything but
  # exactly 16 characters. The CSRF key is 32 for the same kind of reason.
  # These are Harbor's requirements, not preferences.
  testTheLengthsAreHarborsRequirements = {
    expr = {
      secretKey = generators."harbor-secret-key-generator".length;
      xsrf = generators."harbor-xsrf-generator".length;
    };
    expected = {
      secretKey = 16;
      xsrf = 32;
    };
  };

  # Several are read out of env vars by Go that does not quote them, and the
  # chart puts two into a connection string.
  testNoSymbolsInAnyOfThem = {
    expr = lib.unique (lib.mapAttrsToList (_: g: g.symbols) generators);
    expected = [ 0 ];
  };

  # ---- the registry it provides ----------------------------------------

  # A pull happens outside the pod network, so an in-cluster Service address
  # does not resolve from a node's container runtime. The routed host does.
  testThePullRefIsRoutable = {
    expr = r.provides.registry.pullRef;
    expected = "harbor.stub.test";
  };

  # A consumer pushing to a registry that wants credentials has to know before
  # it tries; finding out from a 401 in a Job's log is finding out too late.
  testItPublishesItsCredentials = {
    expr = r.provides.registry.credentials;
    expected = {
      name = "harbor-admin";
      namespace = "harbor";
      usernameKey = "harbor-user";
      passwordKey = "HARBOR_ADMIN_PASSWORD";
    };
  };

  # ---- OIDC ------------------------------------------------------------

  testItRegistersItsOwnClient = {
    expr = r.bundles.harbor.resources.oauth2-client.spec.redirectUrl;
    expected = [ "https://harbor.stub.test/c/oidc/callback" ];
  };

  # Two writers outside this bundle's manifests: cert-manager for the token
  # CA, kaniop for the OIDC client. Nothing here creates either.
  testTheClientSecretIsExternal = {
    expr = r.bundles.harbor.externalSecrets;
    expected = [
      "harbor/harbor-token-ca"
      "harbor/harbor-kanidm-oauth2-credentials"
    ];
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

  # Several hundred megabytes of vulnerability database on every start. A lab
  # that wants scanning turns it on knowing that.
  testScanningIsOffByDefault = {
    expr = values.trivy.enabled;
    expected = false;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };
}
