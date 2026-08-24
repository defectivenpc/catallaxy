{ lib, pkgs }:

let
  inherit (import ../../lib/floe { inherit lib; }) evalFloe;
  grafana = import ../cluster/grafana;

  baseArgs = {
    args = {
      inherit pkgs;
      cataCharts.grafana = {
        chart = pkgs.emptyDirectory;
      };
    };
  };

  stubUpstream =
    { lib, ... }:
    {
      config._module.freeformType = lib.types.attrs;
      options.floes.gateway.exports = lib.mkOption {
        type = lib.types.attrs;
        default = {
          gatewayName = "stub-gateway";
          namespace = "kube-system";
          defaultTier = "public";
        };
      };
      options.floes.gateway.internalHostnames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      options.floes.gateway.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      options.floes.reloader.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      # The datasource peers, so a case may read the rendered chart values.
      # Disabled, which is what leaves grafana with no datasources at all.
      options.floes.prometheus = datasourcePeer;
      options.floes.loki = datasourcePeer;
      options.floes.tempo = datasourcePeer;
    };

  datasourcePeer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    exports = lib.mkOption {
      type = lib.types.attrs;
      default = {
        url = "";
      };
    };
  };

  client = grantedScopes: {
    clientId = "grafana";
    issuer = "https://idm.test.local/oauth2/openid/grafana";
    clientSecretRef = {
      name = "grafana-kanidm-oauth2-credentials";
      namespace = "kanidm";
      key = "CLIENT_SECRET";
    };
    inherit grantedScopes;
  };

  mk =
    {
      providers ? { },
      oidc ? {
        enable = false;
      },
      # Anything else the case wants on the floe, for the settings that have
      # nothing to do with OIDC.
      extra ? { },
    }:
    evalFloe (
      baseArgs
      // {
        inherit providers;
        floe = grafana;
        cluster = {
          imports = [ stubUpstream ];
          floes.grafana = {
            enable = true;
            domain = "grafana.test.local";
            inherit oidc;
          }
          // extra;
        };
      }
    );

  failures = r: map (a: a.message) (builtins.filter (a: !a.assertion) r.config.assertions);

  underGranted = mk {
    providers.kanidm.oauth2Clients.grafana = client [ "openid" ];
    oidc = {
      enable = true;
      scopes = [
        "openid"
        "groups"
      ];
    };
  };

  fullyGranted = mk {
    providers.kanidm.oauth2Clients.grafana = client [
      "openid"
      "groups"
    ];
    oidc = {
      enable = true;
      scopes = [
        "openid"
        "groups"
      ];
    };
  };

  noProvider = mk {
    oidc = {
      enable = true;
      scopes = [
        "openid"
        "groups"
      ];
    };
  };

  oidcOff = mk {
    providers.kanidm.oauth2Clients.grafana = client [ ];
    oidc.enable = false;
  };

  # A lab that brings its own admin Secret, so nothing is minted for it.
  ownAdminSecret = mk {
    extra.adminCredentialsSecret = "my-own-grafana-admin";
  };

  chartValuesOf = r: r.config.bundles.grafana.helmCharts.grafana.values;
in
lib.runTests {

  testUnderGrantedScopesFail = {
    expr = builtins.length (failures underGranted);
    expected = 1;
  };

  testFailureNamesTheMissingScope = {
    expr = lib.hasInfix "groups" (builtins.head (failures underGranted));
    expected = true;
  };

  testFullyGrantedPasses = {
    expr = failures fullyGranted;
    expected = [ ];
  };

  testNoProviderStillEvaluates = {
    expr = failures noProvider;
    expected = [ ];
  };

  testNoProviderLeavesClientNull = {
    expr = noProvider.config.floes.grafana.oidc.client;
    expected = null;
  };

  testDisabledOidcEmitsNoScopeAssertion = {
    expr = builtins.any (a: lib.hasInfix "oidc.scopes" a.message) oidcOff.config.assertions;
    expected = false;
  };

  testClientResolvesFromProvider = {
    expr = fullyGranted.config.floes.grafana.oidc.client.clientSecretRef.name;
    expected = "grafana-kanidm-oauth2-credentials";
  };

  # Left to itself the chart renders `admin-password: <randAlphaNum 40>` into
  # the manifest, which puts the credential in the digest and in the Nix
  # store, and rotates it on any re-render. Pointing it at a Secret minted in
  # the cluster is what keeps it out.
  testTheChartIsAlwaysPointedAtAnExistingAdminSecret = {
    expr = (chartValuesOf oidcOff).admin.existingSecret;
    expected = "grafana-admin";
  };

  testTheAdminSecretIsMinted = {
    expr =
      let
        g = oidcOff.config.floes.grafana.secrets.generate.grafana-admin;
      in
      {
        inherit (g) key length namespace;
        user = g.extraData.admin-user;
      };
    expected = {
      key = "admin-password";
      length = 40;
      namespace = "grafana";
      user = "admin";
    };
  };

  # The chart mounts both keys into the Deployment, so the pod would sit in
  # CreateContainerConfigError if the bundle did not wait for the Secret.
  testTheBundleWaitsForTheMintedSecret = {
    expr = builtins.elem "secret:grafana/grafana-admin" oidcOff.config.bundles.grafana.requires;
    expected = true;
  };

  testALabsOwnSecretIsUsedInstead = {
    expr = (chartValuesOf ownAdminSecret).admin.existingSecret;
    expected = "my-own-grafana-admin";
  };

  # Nothing is minted for a Secret the lab already owns.
  testALabsOwnSecretIsNotMinted = {
    expr = ownAdminSecret.config.floes.grafana.secrets.generate;
    expected = { };
  };
}
