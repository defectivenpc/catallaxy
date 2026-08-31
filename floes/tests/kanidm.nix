# kanidm, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  evalWith =
    inputs:
    support.evalFloe {
      name = "kanidm";
      inputs = {
        domain = "idm.stub.test";
      }
      // inputs;
    };
  r = evalWith { };
  cr = r.bundles.server.resources.kanidm;
in
lib.runTests {

  # No fan-in and no client list. Six consumers used to index an
  # `oauth2Clients` attrset by an id each had invented; kaniop registers the
  # CRD, so a client is an ordinary resource its own consumer renders.
  testItPublishesNoClients = {
    expr = r.provides.oidc ? clients || r.provides.oidc ? oauth2Clients;
    expected = false;
  };

  # What a consumer needs to *build* a client, rather than to look one up.
  testTheProvideSaysHowToRegisterAClient = {
    expr = {
      inherit (r.provides.oidc) clientCrd ref;
    };
    expected = {
      clientCrd = "kaniop.rs/KanidmOAuth2Client";
      ref = {
        name = "kanidm";
        namespace = "kanidm";
      };
    };
  };

  # An empty selector is "every namespace". Absent, kaniop looks only in its
  # own: a consumer's client elsewhere is admitted, stored, and never
  # reconciled, and the consumer waits for a Secret that is not coming.
  testClientsMayLiveInTheirConsumersNamespace = {
    expr = cr.spec ? oauth2ClientNamespaceSelector;
    expected = true;
  };

  testThatIsSaidOnTheSignatureToo = {
    expr = r.provides.oidc.clientsAnyNamespace;
    expected = true;
  };

  testTurningItOffDropsTheSelector = {
    expr =
      (evalWith { clientsAnyNamespace = false; }).bundles.server.resources.kanidm.spec
      ? oauth2ClientNamespaceSelector;
    expected = false;
  };

  # The domain goes into WebAuthn's relying-party id and every token's issuer
  # claim, so it must match the hostname clients actually reach.
  testTheIssuerIsTheDomainOverTls = {
    expr = r.provides.oidc.issuer;
    expected = "https://idm.stub.test";
  };

  # Kanidm has no plaintext mode — WebAuthn needs a secure context — so it
  # mints a certificate rather than assuming one.
  testItMintsItsOwnCertificate = {
    expr = r.bundles.server.resources.kanidm-cert.spec.dnsNames;
    expected = [ "idm.stub.test" ];
  };

  testItDeclaresTheCertificateSecret = {
    expr = r.bundles.server.secrets;
    expected = [ "kanidm/kanidm-tls" ];
  };

  # The operator sets this once the server answers. Waiting on the StatefulSet
  # would report ready while kanidm was still replaying its database.
  testReadinessIsTheOperatorsVerdict = {
    expr = r.bundles.server.ready.resource;
    expected = "kanidm/kanidm";
  };

  # The operator picks the image from `spec.version`, and what it picks is not
  # visible at eval. A claim here would be a claim about someone else's choice.
  testItDoesNotClaimImagesItCannotSee = {
    expr = r.component.imagesComplete;
    expected = false;
  };
}
