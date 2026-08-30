# A floe minting its own credential.
#
# Every case here is an invariant with an incident behind it, ported from the
# parked suite. The generated CRDs are free-form to the schema, so eval
# succeeding proves nothing about the keys: each case reads the field it cares
# about.
{ lib }:

let
  floe = import ../floe-core { inherit lib; };
  kinds = import ../floe-catallaxy/component.nix { inherit lib floe; };

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
  # A generator runs again on every refresh, so anything but zero replaces the
  # value underneath whatever already read it.
  testTheValueIsMintedOnceAndNotRotated = {
    expr = (esOf plain).spec.refreshInterval;
    expected = "0";
  };

  # The generator's one output is called `password`. A consumer wanting
  # another name gets a rewrite, and only then.
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

  # A template names every key it writes, so it is the only way to put a
  # literal beside the generated value.
  testALiteralCompanionGoesThroughATemplate = {
    expr = (esOf withLiteral).spec.target.template.data;
    expected = {
      admin-password = "{{ .password }}";
      admin-user = "admin";
    };
  };

  # `rewrite` renames the generator's single output and has nowhere to put a
  # second key, so a template must suppress it — the template already reads
  # `.password`, and renaming it would leave it with nothing to read.
  testATemplateSuppressesTheRewrite = {
    expr = (lib.head (esOf withLiteral).spec.dataFrom) ? rewrite;
    expected = false;
  };

  # Under `base64` the key keeps its own name — `encoding` changes what is
  # stored, not what it is called — and `length` counts the bytes the consumer
  # decodes rather than the characters that reach the Secret.
  testBase64GoesThroughTheTemplateToo = {
    expr = (esOf encoded).spec.target.template.data;
    expected = {
      password = "{{ .password | b64enc }}";
    };
  };

  # A consumer that puts the value in a URL or an unquoted config file breaks
  # on symbols, and finding that out at runtime is expensive.
  testSymbolsAreOffByDefault = {
    expr = (genOf plain).spec.symbols;
    expected = 0;
  };

  # The generated schema defaults none of these, so every one has to be set or
  # eval fails against the real CRD.
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

  # external-secrets creates the Secret before it has anything to put in it,
  # so waiting on the object alone lets a consumer start against an empty one.
  testTheProbeWaitsForTheKeyNotJustTheSecret = {
    expr = plain.ready.jsonpath;
    expected = "{.data.password}";
  };

  # The bundle has to claim it, or the cluster's coherence check reports the
  # floe reading a Secret nothing makes.
  testItClaimsTheSecretItMints = {
    expr = plain.secrets;
    expected = [ "app/creds" ];
  };

  # A `generatorRef` naming the wrong API version is admitted and then never
  # reconciles.
  testTheGeneratorRefIsVersioned = {
    expr = (lib.head (esOf plain).spec.dataFrom).sourceRef.generatorRef.apiVersion;
    expected = "generators.external-secrets.io/v1alpha1";
  };
}
