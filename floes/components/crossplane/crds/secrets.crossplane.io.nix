{ lib, k8sTypes }:

let
  inherit (lib) mkOption types;
  inherit (k8sTypes) mkTypedSubmodule mkResource;
in
{
  StoreConfig = mkResource {
    apiVersion = "secrets.crossplane.io/v1alpha1";
    kind = "StoreConfig";
    specType = (
      mkTypedSubmodule {
        options = {
          defaultScope = mkOption {
            type = types.str;
            description = ''
              DefaultScope used for scoping secrets for "cluster-scoped" resources.
              If store type is "Kubernetes", this would mean the default namespace to
              store connection secrets for cluster scoped resources.
              In case of "Vault", this would be used as the default parent path.
              Typically, should be set as Crossplane installation namespace.
            '';
          };
          kubernetes = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  auth = mkOption {
                    type = (
                      mkTypedSubmodule {
                        options = {
                          env = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  name = mkOption {
                                    type = types.str;
                                    description = "Name is the name of an environment variable.";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Env is a reference to an environment variable that contains credentials
                              that must be used to connect to the provider.
                            '';
                          };
                          fs = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  path = mkOption {
                                    type = types.str;
                                    description = "Path is a filesystem path.";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Fs is a reference to a filesystem location that contains credentials that
                              must be used to connect to the provider.
                            '';
                          };
                          secretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = types.str;
                                    description = "The key to select.";
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "Name of the secret.";
                                  };
                                  namespace = mkOption {
                                    type = types.str;
                                    description = "Namespace of the secret.";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              A SecretRef is a reference to a secret key that contains the credentials
                              that must be used to connect to the provider.
                            '';
                          };
                          source = mkOption {
                            type = (
                              types.enum [
                                "None"
                                "Secret"
                                "Environment"
                                "Filesystem"
                              ]
                            );
                            description = "Source of the credentials.";
                          };
                        };
                      }
                    );
                    description = "Credentials used to connect to the Kubernetes API.";
                  };
                };
              })
            );
            default = null;
            description = ''
              Kubernetes configures a Kubernetes secret store.
              If the "type" is "Kubernetes" but no config provided, in cluster config
              will be used.
            '';
          };
          plugin = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  configRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          apiVersion = mkOption {
                            type = types.str;
                            description = "APIVersion of the referenced config.";
                          };
                          kind = mkOption {
                            type = types.str;
                            description = "Kind of the referenced config.";
                          };
                          name = mkOption {
                            type = types.str;
                            description = "Name of the referenced config.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "ConfigRef contains store config reference info.";
                  };
                  endpoint = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "Endpoint is the endpoint of the gRPC server.";
                  };
                };
              })
            );
            default = null;
            description = "Plugin configures External secret store as a plugin.";
          };
          type = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Kubernetes"
                  "Vault"
                  "Plugin"
                ]
              )
            );
            default = null;
            description = ''
              Type configures which secret store to be used. Only the configuration
              block for this store will be used and others will be ignored if provided.
              Default is Kubernetes.
            '';
          };
        };
      }
    );
  };

}
