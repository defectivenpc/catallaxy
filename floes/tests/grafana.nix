# grafana, alone.
#
# Two optional dependencies, so most of this is about what happens at each
# width — three datasources, one, none, and with or without an issuer.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  evalWith =
    {
      inputs ? { },
      without ? [ ],
    }:
    support.evalFloe {
      name = "grafana";
      inputs = {
        chart = "/dev/null";
      }
      // inputs;
      inherit without;
    };

  r = evalWith { inputs.oidc = true; };
  values = r.bundles.grafana.helmCharts.grafana.values;
  dsOf =
    res:
    map (
      d: d.type
    ) res.bundles.grafana.helmCharts.grafana.values.datasources."datasources.yaml".datasources;
in
lib.runTests {

  # ---- datasources, at each width --------------------------------------

  # One per backend that resolved. The parked floe read three sibling floes'
  # `enable` flags, had a URL option to override each, and an assertion apiece.
  testEveryResolvedBackendBecomesADatasource = {
    expr = dsOf r;
    expected = [
      "prometheus"
      "loki"
      "tempo"
    ];
  };

  testEndpointsComeFromTheSignatures = {
    expr = map (d: d.url) values.datasources."datasources.yaml".datasources;
    expected = [
      support.stubs.metricsIngest.value.queryUrl
      support.stubs.logIngest.value.queryUrl
      support.stubs.traceIngest.value.queryUrl
    ];
  };

  testAMissingBackendIsAMissingDatasource = {
    expr = dsOf (evalWith {
      inputs.oidc = true;
      without = [ "traceIngest" ];
    });
    expected = [
      "prometheus"
      "loki"
    ];
  };

  # A dashboard with no default datasource opens on an error rather than a
  # panel, so whichever metrics backend is there is the default.
  testMetricsIsTheDefault = {
    expr = (lib.head values.datasources."datasources.yaml".datasources).isDefault;
    expected = true;
  };

  # A Grafana with no datasource renders, comes up healthy, and shows nothing.
  testNoBackendAtAllIsRefused = {
    expr =
      map (a: a.assertion)
        (evalWith {
          without = [
            "metricsIngest"
            "logIngest"
            "traceIngest"
          ];
        }).component.assertions;
    expected = [ false ];
  };

  # ---- OIDC ------------------------------------------------------------

  # Grafana registers its own client. Nothing collects a request, and kanidm
  # does not know grafana exists.
  testItRegistersItsOwnClient = {
    expr = {
      inherit (r.bundles.grafana.resources.oauth2-client.spec) kanidmRef redirectUrl;
    };
    expected = {
      kanidmRef = support.stubs.oidcProvider.value.ref;
      redirectUrl = [ "https://grafana.stub.test/login/generic_oauth" ];
    };
  };

  # The client id is minted by the operator and does not exist at eval, so
  # both values arrive as environment variables and the ini interpolates them.
  # A literal here would be a credential in a rendered manifest.
  testTheCredentialsAreNeverInTheConfig = {
    expr = values."grafana.ini"."auth.generic_oauth".client_secret;
    expected = "\${__env{GF_OAUTH_CLIENT_SECRET}}";
  };

  testTheyComeFromTheSecretKaniopWrites = {
    expr = values.envValueFrom.GF_OAUTH_CLIENT_SECRET.secretKeyRef;
    expected = {
      name = "grafana-kanidm-oauth2-credentials";
      key = "CLIENT_SECRET";
    };
  };

  # Both Secrets this bundle causes, and it causes them two different ways:
  # external-secrets mints the admin password from a generator here, and
  # kaniop writes the client credentials in response to the CR here. Neither
  # is a `needsSecrets` — a bundle looking for someone else to have made what
  # it makes itself.
  # Two Secrets, declared two different ways, because they arrive two
  # different ways. The admin password's ExternalSecret is a resource in this
  # bundle, so this bundle causes it. The client credentials are minted by
  # kaniop — an operator belonging to another floe — in response to the CR
  # here, so nothing in the manifest stream creates them and `cata lab lint`
  # would otherwise call the Deployment's reference dangling.
  testItDeclaresWhatItCausesAndWhatArrives = {
    expr = {
      inherit (r.bundles.grafana) secrets externalSecrets;
    };
    expected = {
      secrets = [ "monitoring/grafana-admin" ];
      externalSecrets = [ "monitoring/grafana-kanidm-oauth2-credentials" ];
    };
  };

  # Left to the chart, the admin password is minted while rendering: it lands
  # in the manifest, in the digest that pins it, and in the Nix store, and it
  # changes on every re-render. `secret-material` refuses that and caught this
  # floe doing it.
  testTheAdminPasswordIsNotRendered = {
    expr = values.admin.existingSecret;
    expected = "grafana-admin";
  };

  testNoClientUnlessAsked = {
    expr = (evalWith { }).bundles.grafana.resources ? oauth2-client;
    expected = false;
  };

  # Silently falling back to the admin password would be a Grafana whose login
  # is not what the lab asked for, with nothing saying so.
  testAskingWithNoIssuerIsRefused = {
    expr =
      support.fails
        (evalWith {
          inputs.oidc = true;
          without = [ "oidcProvider" ];
        }).bundles;
    expected = true;
  };

  # Hiding the form without disabling it leaves the admin password reachable
  # by anyone who knows the URL, so both move together.
  testAutoLoginDisablesTheFormToo = {
    expr =
      let
        a =
          (evalWith {
            inputs = {
              oidc = true;
              autoLogin = true;
            };
          }).bundles.grafana.helmCharts.grafana.values."grafana.ini".auth;
      in
      [
        a.disable_login_form
        a.oauth_auto_login
      ];
    expected = [
      true
      true
    ];
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

}
