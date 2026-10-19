{
  lib,
  floeCore,
  specFile,
}:

let
  floe = import ../floe-catallaxy/authoring/prelude.nix { inherit lib floeCore; };
  kinds = import ../floe-catallaxy/domain/component.nix {
    inherit lib floe;
    k8sApi = import ../kubernetes/api.nix {
      inherit lib floeCore specFile;
      crdGroups = { };
    };
  };

  plain = kinds.mkGeneratedSecret {
    namespace = "app";
    secret = "creds";
  };

  renamed = kinds.mkGeneratedSecret {
    namespace = "app";
    secret = "creds";
    key = "token";
  };

  withLiteral = kinds.mkGeneratedSecret {
    namespace = "app";
    secret = "grafana-admin";
    key = "admin-password";
    extraData.admin-user = "admin";
  };

  encoded = kinds.mkGeneratedSecret {
    namespace = "app";
    secret = "enc-key";
    encoding = "base64";
    length = 32;
  };

  esOf =
    g:
    g.resources."${lib.head (
      lib.attrNames (lib.filterAttrs (n: _: lib.hasSuffix "-external-secret" n) g.resources)
    )}";
  genOf =
    g:
    g.resources."${lib.head (
      lib.attrNames (lib.filterAttrs (n: _: lib.hasSuffix "-generator" n) g.resources)
    )}";
in
lib.runTests {
  testTheValueIsMintedOnceAndNotRotated = {
    expr = (esOf plain).spec.refreshInterval;
    expected = "0";
  };

  testADifferentKeyIsARewrite = {
    expr = (lib.head (esOf renamed).spec.dataFrom).rewrite;
    expected = [
      {
        regexp = {
          source = "^password$";
          target = "token";
        };
      }
    ];
  };

  testTheDefaultKeyNeedsNoRewrite = {
    expr = (lib.head (esOf plain).spec.dataFrom) ? rewrite;
    expected = false;
  };

  testALiteralCompanionGoesThroughATemplate = {
    expr = (esOf withLiteral).spec.target.template.data;
    expected = {
      admin-password = "{{ .password }}";
      admin-user = "admin";
    };
  };

  testATemplateSuppressesTheRewrite = {
    expr = (lib.head (esOf withLiteral).spec.dataFrom) ? rewrite;
    expected = false;
  };

  testBase64GoesThroughTheTemplateToo = {
    expr = (esOf encoded).spec.target.template.data;
    expected = {
      password = "{{ .password | b64enc }}";
    };
  };

  testSymbolsAreOffByDefault = {
    expr = (genOf plain).spec.symbols;
    expected = 0;
  };

  testTheGeneratorSpecIsComplete = {
    expr = lib.sort (a: b: a < b) (lib.attrNames (genOf plain).spec);
    expected = [
      "allowRepeat"
      "digits"
      "length"
      "noUpper"
      "symbolCharacters"
      "symbols"
    ];
  };

  testTheProbeWaitsForTheKeyNotJustTheSecret = {
    expr = plain.ready.jsonpath;
    expected = "{.data.password}";
  };

  testItClaimsTheSecretItMints = {
    expr = plain.secrets;
    expected = [ "app/creds" ];
  };

  testTheGeneratorRefIsVersioned = {
    expr = (lib.head (esOf plain).spec.dataFrom).sourceRef.generatorRef.apiVersion;
    expected = "generators.external-secrets.io/v1alpha1";
  };
}
