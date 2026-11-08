{ lib, floe }:

let
  T = floe.T;
in
{
  X509_ISSUANCE = floe.mkSig {
    name = "X509_ISSUANCE";
    canonicalName = "issuance";

    behaviour = [ "issuers-ready" ];
    description = "Something that signs certificates, and whether a browser will trust what it signs.";
    fields = {
      publicIssuer = T.bool;

      issuerRef = (
        T.record {
          name = T.str;
          kind = T.str;
        }
      );

      caSecret = (
        T.nullOr (
          T.record {
            name = T.str;
            key = T.str;
            namespace = T.k8sName;
          }
        )
      );
    };
  };

  TRUST_BUNDLE = floe.mkSig {
    name = "TRUST_BUNDLE";
    canonicalName = "trust";
    description = "A CA bundle distributed into namespaces, for workloads that verify the lab's own certificates.";
    fields = {
      namespace = T.k8sName;

      secretTargets = T.bool;

      caBundle = (
        T.record {
          name = T.str;
          key = T.str;
        }
      );

      caBundleSecret = (
        T.nullOr (
          T.record {
            name = T.str;
            key = T.str;
          }
        )
      );
    };
  };

  LAB_CA = floe.mkSig {
    name = "LAB_CA";
    canonicalName = "labCa";
    description = "The lab's own root: where its certificate and key are on the host, and where it lands in a cluster.";
    fields = {
      pem = T.str;

      caCert = T.str;

      secret = T.record {
        namespace = T.k8sName;
        name = T.str;
      };
    };
  };
}
