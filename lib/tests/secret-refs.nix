{ lib }:

let
  sr = import ../eval/secret-refs.nix { inherit lib; };

  ns = name: {
    inherit name;
    namespace = "ns";
  };
in
lib.runTests {

  testAPlainSecretIsMade = {
    expr = sr.secretsCreatedBy {
      kind = "Secret";
      metadata = ns "creds";
    };
    expected = [ "ns/creds" ];
  };

  testACertificateMakesItsSecret = {
    expr = sr.secretsCreatedBy {
      kind = "Certificate";
      metadata = ns "c";
      spec.secretName = "tls";
    };
    expected = [ "ns/tls" ];
  };

  testACertificateDoesNotReadItsSecret = {
    expr = sr.secretsUsedBy {
      kind = "Certificate";
      metadata = ns "c";
      spec.secretName = "tls";
    };
    expected = [ ];
  };

  testAnExternalSecretMakesItsTarget = {
    expr = sr.secretsCreatedBy {
      kind = "ExternalSecret";
      metadata = ns "e";
      spec.target.name = "minted";
    };
    expected = [ "ns/minted" ];
  };

  testAnExternalSecretWithNoTargetUsesItsOwnName = {
    expr = sr.secretsCreatedBy {
      kind = "ExternalSecret";
      metadata = ns "e";
      spec = { };
    };
    expected = [ "ns/e" ];
  };

  testEveryWayAPodNamesASecret = {
    expr = sr.secretsUsedBy {
      kind = "Deployment";
      metadata = ns "d";
      spec.template.spec = {
        imagePullSecrets = [ { name = "pull"; } ];
        volumes = [ { secret.secretName = "vol"; } ];
        containers = [
          {
            env = [ { valueFrom.secretKeyRef.name = "env"; } ];
            envFrom = [ { secretRef.name = "bulk"; } ];
          }
        ];
      };
    };
    expected = [
      "ns/bulk"
      "ns/env"
      "ns/pull"
      "ns/vol"
    ];
  };

  testAGatewayListenerNamesItsCertificate = {
    expr = sr.secretsUsedBy {
      kind = "Gateway";
      metadata = ns "g";
      spec.listeners = [ { tls.certificateRefs = [ { name = "gw-tls"; } ]; } ];
    };
    expected = [ "ns/gw-tls" ];
  };

  testACertificateRefOfAnotherKindIsNotASecret = {
    expr = sr.secretsUsedBy {
      kind = "Gateway";
      metadata = ns "g";
      spec.listeners = [
        {
          tls.certificateRefs = [
            {
              name = "other";
              kind = "ConfigMap";
            }
          ];
        }
      ];
    };
    expected = [ ];
  };

  testATrustBundleReadsItsSource = {
    expr = sr.secretsUsedBy {
      kind = "Bundle";
      metadata = ns "b";
      spec.sources = [
        {
          secret = {
            name = "ca";
            key = "tls.crt";
          };
        }
      ];
    };
    expected = [ "ns/ca" ];
  };

  testAClusterScopedResourceIsSkipped = {
    expr = sr.secretsUsedBy {
      kind = "ClusterIssuer";
      metadata.name = "i";
      spec.ca.secretName = "ca";
    };
    expected = [ ];
  };

  testAClusterScopedResourceProvidesNothingEither = {
    expr = sr.secretsCreatedBy {
      kind = "Secret";
      metadata.name = "no-namespace";
    };
    expected = [ ];
  };

  testAStoreReferenceIsNotASecretReference = {
    expr = sr.secretsUsedBy {
      kind = "ExternalSecret";
      metadata = ns "e";
      spec = {
        secretStoreRef.name = "vault";
        target.name = "minted";
      };
    };
    expected = [ ];
  };
}
