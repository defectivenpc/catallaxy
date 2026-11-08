{ lib, floe }:

let
  T = floe.T;
in
{
  LAB_SECRET_STORE = floe.mkSig {
    name = "LAB_SECRET_STORE";
    canonicalName = "labStore";
    description = "A store on the operator's machine that `cata` reads authored secret values from.";
    fields = {
      name = T.str;

      writable = T.bool;

      backend = T.enum [
        "sops"
        "env"
        "vault"
        "external"
      ];

      writerCommand = T.nullOr (T.listOf T.str);
      removerCommand = T.nullOr (T.listOf T.str);

      vault = T.record {
        server = T.nullOr T.str;
        path = T.str;
        version = T.enum [
          "v1"
          "v2"
        ];
      };
    };
  };

  LAB_SECRET = floe.mkSig {
    name = "LAB_SECRET";
    canonicalName = "labSecret";
    description = "A secret the lab holds on the operator's machine, and the keys a cluster may read from it.";
    fields = {
      name = T.str;

      store = T.str;

      kind = T.enum [
        "value"
        "ca"
      ];

      readableKeys = T.listOf T.str;

      keys = T.attrsOf (
        T.record {
          generator = T.nullOr (
            T.enum [
              "base64"
              "hex"
              "alphanumeric"
              "uuid"
            ]
          );
          length = T.nullOr T.int;
        }
      );

      hostPaths = T.attrsOf T.str;
    };
  };

  SECRET_STORE = floe.mkSig {
    name = "SECRET_STORE";
    canonicalName = "secretStore";
    description = "A named store an ExternalSecret reads from, and whether it may be written to.";
    fields = {

      storeName = T.str;
      storeKind = (
        T.enum [
          "SecretStore"
          "ClusterSecretStore"
        ]
      );

      writable = T.bool;
    };
  };

  PUBLISHED_SECRET = floe.mkSig {
    name = "PUBLISHED_SECRET";
    canonicalName = "publication";
    description = "A value one cluster pushed into a lab store, and where to read it.";
    fields = {
      storeName = T.str;

      key = T.str;

      keys = T.listOf T.str;
    };
  };

  VAULT_SERVER = floe.mkSig {
    name = "VAULT_SERVER";
    canonicalName = "vault";
    description = "A Vault-compatible server: where it answers, its KV mount, and whether it unseals itself.";
    fields = {

      address = T.str;

      kvPath = T.str;
      kvVersion = (
        T.enum [
          "v1"
          "v2"
        ]
      );

      tokenSecret = (
        T.record {
          namespace = T.k8sName;
          name = T.k8sName;
          key = T.str;
        }
      );

      autoUnseals = T.bool;
    };
  };
}
