# What counts as making a Secret, and what counts as reading one.
#
# The distinction is the whole point of the file under test: the parked walker
# treated any `secretName` as a read, which made cert-manager a consumer of its
# own output. Every case here is one of the two directions.
{ lib }:

let
  sr = import ../eval/secret-refs.nix { inherit lib; };

  ns = name: {
    inherit name;
    namespace = "ns";
  };
in
lib.runTests {
  # ---- production -------------------------------------------------------

  testAPlainSecretIsMade = {
    expr = sr.secretsCreatedBy {
      kind = "Secret";
      metadata = ns "creds";
    };
    expected = [ "ns/creds" ];
  };

  # The case the parked walker got backwards.
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

  # external-secrets defaults the target to the ExternalSecret's own name, so
  # a bundle omitting `target` still provides something.
  testAnExternalSecretWithNoTargetUsesItsOwnName = {
    expr = sr.secretsCreatedBy {
      kind = "ExternalSecret";
      metadata = ns "e";
      spec = { };
    };
    expected = [ "ns/e" ];
  };

  # ---- consumption ------------------------------------------------------

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

  # `certificateRefs` defaults to Secret but may name another kind, and a
  # reference to something that is not a Secret is not a missing Secret.
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

  # ---- what is deliberately not answered --------------------------------

  # A ClusterIssuer resolves `spec.ca.secretName` against the controller's
  # resource namespace, which is not on the resource. Guessing would invent a
  # reference; the floe says so with `needsSecrets` instead.
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

  # An ExternalSecret names its store in `secretStoreRef`, which is a store,
  # not a Secret. Ordering against it already has its own token.
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
