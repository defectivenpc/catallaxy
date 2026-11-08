{ lib, floe }:

let
  T = floe.T;
in
{
  OIDC_PROVIDER = floe.mkSig {
    name = "OIDC_PROVIDER";
    canonicalName = "oidc";
    description = "An OIDC issuer, its endpoints, and the CR a consumer registers a client with.";
    fields = {

      issuer = T.str;

      authorizationEndpoint = T.str;
      tokenEndpoint = T.str;

      clientCrd = T.str;

      ref = (
        T.record {
          name = T.k8sName;
          namespace = T.k8sName;
        }
      );

      clientsAnyNamespace = T.bool;
    };
  };

  GIT_REPOSITORY = floe.mkSig {
    name = "GIT_REPOSITORY";
    canonicalName = "git";
    description = "A git remote, addressed differently from inside and outside the cluster.";
    fields = {

      internalUrl = T.str;

      externalUrl = T.str;

      cloneUrl = T.str;

      credentials = (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
            username = T.str;

            usernameKey = T.str;
            passwordKey = T.str;
          }
        )
      );
    };
  };

  CONFIG_RELOAD = floe.mkSig {
    name = "CONFIG_RELOAD";
    canonicalName = "reload";
    description = "The annotations that make a workload restart when a Secret or ConfigMap it mounts changes.";
    fields = {
      secretAnnotation = T.str;
      configMapAnnotation = T.str;
    };
  };

  OBJECT_STORE = floe.mkSig {
    name = "OBJECT_STORE";
    canonicalName = "objectStore";
    description = "An S3-compatible endpoint and the credentials, if any, needed to reach it.";
    fields = {
      namespace = T.k8sName;
      s3Endpoint = T.str;

      credentials = (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
            accessKeyKey = T.str;
            secretKeyKey = T.str;
          }
        )
      );
    };
  };

  OCI_REGISTRY = floe.mkSig {
    name = "OCI_REGISTRY";
    canonicalName = "registry";
    description = "A container registry, addressed for a human and for a node pulling an image.";
    fields = {
      namespace = T.k8sName;
      url = T.str;
      pullRef = T.str;

      credentials = (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;

            usernameKey = T.str;
            passwordKey = T.str;
          }
        )
      );
    };
  };
}
