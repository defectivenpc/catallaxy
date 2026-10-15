{ lib, k8sTypes }:

let
  inherit (lib) mkOption types;
  inherit (k8sTypes) mkTypedSubmodule mkResource;
in
{
  ACRAccessToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "ACRAccessToken";
    specType = (
      mkTypedSubmodule {
        options = {
          auth = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  managedIdentity = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          identityId = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "If multiple Managed Identity is assigned to the pod, you can select the one to be used";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "ManagedIdentity uses Azure Managed Identity to authenticate with Azure.";
                  };
                  servicePrincipal = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          secretRef = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  clientId = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "The Azure clientId of the service principle used for authentication.";
                                  };
                                  clientSecret = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "The Azure ClientSecret of the service principle used for authentication.";
                                  };
                                };
                              }
                            );
                            description = ''
                              Configuration used to authenticate with Azure using static
                              credentials stored in a Kind=Secret.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = "ServicePrincipal uses Azure Service Principal credentials to authenticate with Azure.";
                  };
                  workloadIdentity = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          serviceAccountRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  audiences = mkOption {
                                    type = (types.nullOr (types.listOf types.str));
                                    default = null;
                                    description = ''
                                      Audience specifies the `aud` claim for the service account token
                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                      then this audiences will be appended to the list
                                    '';
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the ServiceAccount resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Namespace of the resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              ServiceAccountRef specified the service account
                              that should be used when authenticating with WorkloadIdentity.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = "WorkloadIdentity uses Azure Workload Identity to authenticate with Azure.";
                  };
                };
              }
            );
          };
          environmentType = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "PublicCloud"
                  "USGovernmentCloud"
                  "ChinaCloud"
                  "GermanCloud"
                ]
              )
            );
            default = null;
            description = ''
              EnvironmentType specifies the Azure cloud environment endpoints to use for
              connecting and authenticating with Azure. By default it points to the public cloud AAD endpoint.
              The following endpoints are available, also see here: https://github.com/Azure/go-autorest/blob/main/autorest/azure/environments.go#L152
              PublicCloud, USGovernmentCloud, ChinaCloud, GermanCloud
            '';
          };
          registry = mkOption {
            type = types.str;
            description = ''
              the domain name of the ACR registry
              e.g. foobarexample.azurecr.io
            '';
          };
          scope = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              Define the scope for the access token, e.g. pull/push access for a repository.
              if not provided it will return a refresh token that has full scope.
              Note: you need to pin it down to the repository level, there is no wildcard available.

              examples:
              repository:my-repository:pull,push
              repository:my-repository:pull

              see docs for details: https://docs.docker.com/registry/spec/auth/scope/
            '';
          };
          tenantId = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "TenantID configures the Azure Tenant to send requests to. Required for ServicePrincipal auth type.";
          };
        };
      }
    );
  };

  ClusterGenerator = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "ClusterGenerator";
    specType = (
      mkTypedSubmodule {
        options = {
          generator = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  acrAccessTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          auth = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  managedIdentity = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          identityId = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "If multiple Managed Identity is assigned to the pod, you can select the one to be used";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "ManagedIdentity uses Azure Managed Identity to authenticate with Azure.";
                                  };
                                  servicePrincipal = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          secretRef = mkOption {
                                            type = (
                                              mkTypedSubmodule {
                                                options = {
                                                  clientId = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = "The Azure clientId of the service principle used for authentication.";
                                                  };
                                                  clientSecret = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = "The Azure ClientSecret of the service principle used for authentication.";
                                                  };
                                                };
                                              }
                                            );
                                            description = ''
                                              Configuration used to authenticate with Azure using static
                                              credentials stored in a Kind=Secret.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "ServicePrincipal uses Azure Service Principal credentials to authenticate with Azure.";
                                  };
                                  workloadIdentity = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          serviceAccountRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              ServiceAccountRef specified the service account
                                              that should be used when authenticating with WorkloadIdentity.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "WorkloadIdentity uses Azure Workload Identity to authenticate with Azure.";
                                  };
                                };
                              }
                            );
                          };
                          environmentType = mkOption {
                            type = (
                              types.nullOr (
                                types.enum [
                                  "PublicCloud"
                                  "USGovernmentCloud"
                                  "ChinaCloud"
                                  "GermanCloud"
                                ]
                              )
                            );
                            default = null;
                            description = ''
                              EnvironmentType specifies the Azure cloud environment endpoints to use for
                              connecting and authenticating with Azure. By default it points to the public cloud AAD endpoint.
                              The following endpoints are available, also see here: https://github.com/Azure/go-autorest/blob/main/autorest/azure/environments.go#L152
                              PublicCloud, USGovernmentCloud, ChinaCloud, GermanCloud
                            '';
                          };
                          registry = mkOption {
                            type = types.str;
                            description = ''
                              the domain name of the ACR registry
                              e.g. foobarexample.azurecr.io
                            '';
                          };
                          scope = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              Define the scope for the access token, e.g. pull/push access for a repository.
                              if not provided it will return a refresh token that has full scope.
                              Note: you need to pin it down to the repository level, there is no wildcard available.

                              examples:
                              repository:my-repository:pull,push
                              repository:my-repository:pull

                              see docs for details: https://docs.docker.com/registry/spec/auth/scope/
                            '';
                          };
                          tenantId = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "TenantID configures the Azure Tenant to send requests to. Required for ServicePrincipal auth type.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      ACRAccessTokenSpec defines how to generate the access token
                      e.g. how to authenticate and which registry to use.
                      see: https://github.com/Azure/acr/blob/main/docs/AAD-OAuth.md#overview
                    '';
                  };
                  ecrAuthorizationTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          auth = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  jwt = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          serviceAccountRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "A reference to a ServiceAccount resource.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "Authenticate against AWS using service account tokens.";
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          accessKeyIDSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The AccessKeyID is used for authentication";
                                          };
                                          secretAccessKeySecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The SecretAccessKey is used for authentication";
                                          };
                                          sessionTokenSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              The SessionToken used for authentication
                                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      AWSAuthSecretRef holds secret references for AWS credentials
                                      both AccessKeyID and SecretAccessKey must be defined in order to properly authenticate.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "Auth defines how to authenticate with AWS";
                          };
                          region = mkOption {
                            type = types.str;
                            description = "Region specifies the region to operate in.";
                          };
                          role = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              You can assume a role before making calls to the
                              desired AWS service.
                            '';
                          };
                          scope = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              Scope specifies the ECR service scope.
                              Valid options are private and public.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  fakeSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          controller = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              Used to select the correct ESO controller (think: ingress.ingressClassName)
                              The ESO controller is instantiated with a specific controller name and filters VDS based on this property
                            '';
                          };
                          data = mkOption {
                            type = (types.nullOr (types.attrsOf types.str));
                            default = null;
                            description = ''
                              Data defines the static data returned
                              by this generator.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = "FakeSpec contains the static data.";
                  };
                  gcrAccessTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          auth = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          secretAccessKeySecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The SecretAccessKey is used for authentication";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                  };
                                  workloadIdentity = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          clusterLocation = mkOption {
                                            type = types.str;
                                          };
                                          clusterName = mkOption {
                                            type = types.str;
                                          };
                                          clusterProjectID = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                          };
                                          serviceAccountRef = mkOption {
                                            type = (
                                              mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              }
                                            );
                                            description = "A reference to a ServiceAccount resource.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                  };
                                };
                              }
                            );
                            description = "Auth defines the means for authenticating with GCP";
                          };
                          projectID = mkOption {
                            type = types.str;
                            description = "ProjectID defines which project to use to authenticate with";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  githubAccessTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          appID = mkOption {
                            type = types.str;
                          };
                          auth = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  privateKey = mkOption {
                                    type = (
                                      mkTypedSubmodule {
                                        options = {
                                          secretRef = mkOption {
                                            type = (
                                              mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              }
                                            );
                                            description = ''
                                              A reference to a specific 'key' within a Secret resource.
                                              In some instances, `key` is a required field.
                                            '';
                                          };
                                        };
                                      }
                                    );
                                  };
                                };
                              }
                            );
                            description = "Auth configures how ESO authenticates with a Github instance.";
                          };
                          installID = mkOption {
                            type = types.str;
                          };
                          permissions = mkOption {
                            type = (types.nullOr (types.attrsOf types.str));
                            default = null;
                            description = "Map of permissions the token will have. If omitted, defaults to all permissions the GitHub App has.";
                          };
                          repositories = mkOption {
                            type = (types.nullOr (types.listOf types.str));
                            default = null;
                            description = ''
                              List of repositories the token will have access to. If omitted, defaults to all repositories the GitHub App
                              is installed to.
                            '';
                          };
                          url = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "URL configures the Github instance URL. Defaults to https://github.com/.";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  grafanaSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          auth = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  basic = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          password = mkOption {
                                            type = (
                                              mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The key where the token is found.";
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                };
                                              }
                                            );
                                            description = "A basic auth password used to authenticate against the Grafana instance.";
                                          };
                                          username = mkOption {
                                            type = types.str;
                                            description = "A basic auth username used to authenticate against the Grafana instance.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Basic auth credentials used to authenticate against the Grafana instance.
                                      Note: you need a token which has elevated permissions to create service accounts.
                                      See here for the documentation on basic roles offered by Grafana:
                                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                                    '';
                                  };
                                  token = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The key where the token is found.";
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      A service account token used to authenticate against the Grafana instance.
                                      Note: you need a token which has elevated permissions to create service accounts.
                                      See here for the documentation on basic roles offered by Grafana:
                                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                                    '';
                                  };
                                };
                              }
                            );
                            description = ''
                              Auth is the authentication configuration to authenticate
                              against the Grafana instance.
                            '';
                          };
                          serviceAccount = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  name = mkOption {
                                    type = types.str;
                                    description = "Name is the name of the service account that will be created by ESO.";
                                  };
                                  role = mkOption {
                                    type = types.str;
                                    description = ''
                                      Role is the role of the service account.
                                      See here for the documentation on basic roles offered by Grafana:
                                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                                    '';
                                  };
                                };
                              }
                            );
                            description = ''
                              ServiceAccount is the configuration for the service account that
                              is supposed to be generated by the generator.
                            '';
                          };
                          url = mkOption {
                            type = types.str;
                            description = "URL is the URL of the Grafana instance.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "GrafanaSpec controls the behavior of the grafana generator.";
                  };
                  passwordSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          allowRepeat = mkOption {
                            type = types.bool;
                            description = "set AllowRepeat to true to allow repeating characters.";
                          };
                          digits = mkOption {
                            type = (types.nullOr types.int);
                            default = null;
                            description = ''
                              Digits specifies the number of digits in the generated
                              password. If omitted it defaults to 25% of the length of the password
                            '';
                          };
                          length = mkOption {
                            type = types.int;
                            description = ''
                              Length of the password to be generated.
                              Defaults to 24
                            '';
                          };
                          noUpper = mkOption {
                            type = types.bool;
                            description = "Set NoUpper to disable uppercase characters";
                          };
                          symbolCharacters = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              SymbolCharacters specifies the special characters that should be used
                              in the generated password.
                            '';
                          };
                          symbols = mkOption {
                            type = (types.nullOr types.int);
                            default = null;
                            description = ''
                              Symbols specifies the number of symbol characters in the generated
                              password. If omitted it defaults to 25% of the length of the password
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = "PasswordSpec controls the behavior of the password generator.";
                  };
                  quayAccessTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          robotAccount = mkOption {
                            type = types.str;
                            description = "Name of the robot account you are federating with";
                          };
                          serviceAccountRef = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  audiences = mkOption {
                                    type = (types.nullOr (types.listOf types.str));
                                    default = null;
                                    description = ''
                                      Audience specifies the `aud` claim for the service account token
                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                      then this audiences will be appended to the list
                                    '';
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the ServiceAccount resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Namespace of the resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              }
                            );
                            description = "Name of the service account you are federating with";
                          };
                          url = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "URL configures the Quay instance URL. Defaults to quay.io.";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  stsSessionTokenSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          auth = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  jwt = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          serviceAccountRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "A reference to a ServiceAccount resource.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "Authenticate against AWS using service account tokens.";
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          accessKeyIDSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The AccessKeyID is used for authentication";
                                          };
                                          secretAccessKeySecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The SecretAccessKey is used for authentication";
                                          };
                                          sessionTokenSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              The SessionToken used for authentication
                                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      AWSAuthSecretRef holds secret references for AWS credentials
                                      both AccessKeyID and SecretAccessKey must be defined in order to properly authenticate.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "Auth defines how to authenticate with AWS";
                          };
                          region = mkOption {
                            type = types.str;
                            description = "Region specifies the region to operate in.";
                          };
                          requestParameters = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  serialNumber = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      SerialNumber is the identification number of the MFA device that is associated with the IAM user who is making
                                      the GetSessionToken call.
                                      Possible values: hardware device (such as GAHT12345678) or an Amazon Resource Name (ARN) for a virtual device
                                      (such as arn:aws:iam::123456789012:mfa/user)
                                    '';
                                  };
                                  sessionDuration = mkOption {
                                    type = (types.nullOr types.int);
                                    default = null;
                                    description = ''
                                      SessionDuration The duration, in seconds, that the credentials should remain valid. Acceptable durations for
                                      IAM user sessions range from 900 seconds (15 minutes) to 129,600 seconds (36 hours), with 43,200 seconds
                                      (12 hours) as the default.
                                    '';
                                  };
                                  tokenCode = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "TokenCode is the value provided by the MFA device, if MFA is required.";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "RequestParameters contains parameters that can be passed to the STS service.";
                          };
                          role = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              You can assume a role before making calls to the
                              desired AWS service.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  uuidSpec = mkOption {
                    type = (types.nullOr types.attrs);
                    default = null;
                    description = "UUIDSpec controls the behavior of the uuid generator.";
                  };
                  vaultDynamicSecretSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          allowEmptyResponse = mkOption {
                            type = (types.nullOr types.bool);
                            default = null;
                            description = "Do not fail if no secrets are found. Useful for requests where no data is expected.";
                          };
                          controller = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              Used to select the correct ESO controller (think: ingress.ingressClassName)
                              The ESO controller is instantiated with a specific controller name and filters VDS based on this property
                            '';
                          };
                          method = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "Vault API method to use (GET/POST/other)";
                          };
                          parameters = mkOption {
                            type = (types.nullOr types.anything);
                            default = null;
                            description = "Parameters to pass to Vault write (for non-GET methods)";
                          };
                          path = mkOption {
                            type = types.str;
                            description = "Vault path to obtain the dynamic secret from";
                          };
                          provider = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  auth = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          appRole = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  path = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Path where the App Role authentication backend is mounted
                                                      in Vault, e.g: "approle"
                                                    '';
                                                  };
                                                  roleId = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      RoleID configured in the App Role authentication backend when setting
                                                      up the authentication backend in Vault.
                                                    '';
                                                  };
                                                  roleRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      Reference to a key in a Secret that contains the App Role ID used
                                                      to authenticate with Vault.
                                                      The `key` field must be specified and denotes which entry within the Secret
                                                      resource is used as the app role id.
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      }
                                                    );
                                                    description = ''
                                                      Reference to a key in a Secret that contains the App Role secret used
                                                      to authenticate with Vault.
                                                      The `key` field must be specified and denotes which entry within the Secret
                                                      resource is used as the app role secret.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              AppRole authenticates with Vault using the App Role auth mechanism,
                                              with the role and secret stored in a Kubernetes Secret resource.
                                            '';
                                          };
                                          cert = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  clientCert = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      ClientCert is a certificate to authenticate using the Cert Vault
                                                      authentication method
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      SecretRef to a key in a Secret resource containing client private key to
                                                      authenticate with Vault using the Cert authentication method
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              Cert authenticates with TLS Certificates by passing client certificate, private key and ca certificate
                                              Cert authentication method
                                            '';
                                          };
                                          iam = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  externalID = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "AWS External ID set on assumed IAM roles";
                                                  };
                                                  jwt = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          serviceAccountRef = mkOption {
                                                            type = (
                                                              types.nullOr (mkTypedSubmodule {
                                                                options = {
                                                                  audiences = mkOption {
                                                                    type = (types.nullOr (types.listOf types.str));
                                                                    default = null;
                                                                    description = ''
                                                                      Audience specifies the `aud` claim for the service account token
                                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                                      then this audiences will be appended to the list
                                                                    '';
                                                                  };
                                                                  name = mkOption {
                                                                    type = types.str;
                                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                                  };
                                                                  namespace = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      Namespace of the resource being referred to.
                                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                                    '';
                                                                  };
                                                                };
                                                              })
                                                            );
                                                            default = null;
                                                            description = "A reference to a ServiceAccount resource.";
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = "Specify a service account with IRSA enabled";
                                                  };
                                                  path = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "Path where the AWS auth method is enabled in Vault, e.g: \"aws\"";
                                                  };
                                                  region = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "AWS region";
                                                  };
                                                  role = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "This is the AWS role to be assumed before talking to vault";
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          accessKeyIDSecretRef = mkOption {
                                                            type = (
                                                              types.nullOr (mkTypedSubmodule {
                                                                options = {
                                                                  key = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      A key in the referenced Secret.
                                                                      Some instances of this field may be defaulted, in others it may be required.
                                                                    '';
                                                                  };
                                                                  name = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = "The name of the Secret resource being referred to.";
                                                                  };
                                                                  namespace = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      The namespace of the Secret resource being referred to.
                                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                                    '';
                                                                  };
                                                                };
                                                              })
                                                            );
                                                            default = null;
                                                            description = "The AccessKeyID is used for authentication";
                                                          };
                                                          secretAccessKeySecretRef = mkOption {
                                                            type = (
                                                              types.nullOr (mkTypedSubmodule {
                                                                options = {
                                                                  key = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      A key in the referenced Secret.
                                                                      Some instances of this field may be defaulted, in others it may be required.
                                                                    '';
                                                                  };
                                                                  name = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = "The name of the Secret resource being referred to.";
                                                                  };
                                                                  namespace = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      The namespace of the Secret resource being referred to.
                                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                                    '';
                                                                  };
                                                                };
                                                              })
                                                            );
                                                            default = null;
                                                            description = "The SecretAccessKey is used for authentication";
                                                          };
                                                          sessionTokenSecretRef = mkOption {
                                                            type = (
                                                              types.nullOr (mkTypedSubmodule {
                                                                options = {
                                                                  key = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      A key in the referenced Secret.
                                                                      Some instances of this field may be defaulted, in others it may be required.
                                                                    '';
                                                                  };
                                                                  name = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = "The name of the Secret resource being referred to.";
                                                                  };
                                                                  namespace = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      The namespace of the Secret resource being referred to.
                                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                                    '';
                                                                  };
                                                                };
                                                              })
                                                            );
                                                            default = null;
                                                            description = ''
                                                              The SessionToken used for authentication
                                                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                                                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = "Specify credentials in a Secret object";
                                                  };
                                                  vaultAwsIamServerID = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "X-Vault-AWS-IAM-Server-ID is an additional header used by Vault IAM auth method to mitigate against different types of replay attacks. More details here: https://developer.hashicorp.com/vault/docs/auth/aws";
                                                  };
                                                  vaultRole = mkOption {
                                                    type = types.str;
                                                    description = "Vault Role. In vault, a role describes an identity with a set of permissions, groups, or policies you want to attach a user of the secrets engine";
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              Iam authenticates with vault by passing a special AWS request signed with AWS IAM credentials
                                              AWS IAM authentication method
                                            '';
                                          };
                                          jwt = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  kubernetesServiceAccountToken = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          audiences = mkOption {
                                                            type = (types.nullOr (types.listOf types.str));
                                                            default = null;
                                                            description = ''
                                                              Optional audiences field that will be used to request a temporary Kubernetes service
                                                              account token for the service account referenced by `serviceAccountRef`.
                                                              Defaults to a single audience `vault` it not specified.
                                                              Deprecated: use serviceAccountRef.Audiences instead
                                                            '';
                                                          };
                                                          expirationSeconds = mkOption {
                                                            type = (types.nullOr types.int);
                                                            default = null;
                                                            description = ''
                                                              Optional expiration time in seconds that will be used to request a temporary
                                                              Kubernetes service account token for the service account referenced by
                                                              `serviceAccountRef`.
                                                              Deprecated: this will be removed in the future.
                                                              Defaults to 10 minutes.
                                                            '';
                                                          };
                                                          serviceAccountRef = mkOption {
                                                            type = (
                                                              mkTypedSubmodule {
                                                                options = {
                                                                  audiences = mkOption {
                                                                    type = (types.nullOr (types.listOf types.str));
                                                                    default = null;
                                                                    description = ''
                                                                      Audience specifies the `aud` claim for the service account token
                                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                                      then this audiences will be appended to the list
                                                                    '';
                                                                  };
                                                                  name = mkOption {
                                                                    type = types.str;
                                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                                  };
                                                                  namespace = mkOption {
                                                                    type = (types.nullOr types.str);
                                                                    default = null;
                                                                    description = ''
                                                                      Namespace of the resource being referred to.
                                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                                    '';
                                                                  };
                                                                };
                                                              }
                                                            );
                                                            description = "Service account field containing the name of a kubernetes ServiceAccount.";
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      Optional ServiceAccountToken specifies the Kubernetes service account for which to request
                                                      a token for with the `TokenRequest` API.
                                                    '';
                                                  };
                                                  path = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Path where the JWT authentication backend is mounted
                                                      in Vault, e.g: "jwt"
                                                    '';
                                                  };
                                                  role = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Role is a JWT role to authenticate using the JWT/OIDC Vault
                                                      authentication method
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      Optional SecretRef that refers to a key in a Secret resource containing JWT token to
                                                      authenticate with Vault using the JWT/OIDC authentication method.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              Jwt authenticates with Vault by passing role and JWT token using the
                                              JWT/OIDC authentication method
                                            '';
                                          };
                                          kubernetes = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  mountPath = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Path where the Kubernetes authentication backend is mounted in Vault, e.g:
                                                      "kubernetes"
                                                    '';
                                                  };
                                                  role = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      A required field containing the Vault Role to assume. A Role binds a
                                                      Kubernetes ServiceAccount with a set of Vault policies.
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      Optional secret field containing a Kubernetes ServiceAccount JWT used
                                                      for authenticating with Vault. If a name is specified without a key,
                                                      `token` is the default. If one is not specified, the one bound to
                                                      the controller will be used.
                                                    '';
                                                  };
                                                  serviceAccountRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          audiences = mkOption {
                                                            type = (types.nullOr (types.listOf types.str));
                                                            default = null;
                                                            description = ''
                                                              Audience specifies the `aud` claim for the service account token
                                                              If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                              then this audiences will be appended to the list
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = types.str;
                                                            description = "The name of the ServiceAccount resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              Namespace of the resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      Optional service account field containing the name of a kubernetes ServiceAccount.
                                                      If the service account is specified, the service account secret token JWT will be used
                                                      for authenticating with Vault. If the service account selector is not supplied,
                                                      the secretRef will be used instead.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              Kubernetes authenticates with Vault by passing the ServiceAccount
                                              token stored in the named Secret resource to the Vault server.
                                            '';
                                          };
                                          ldap = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  path = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Path where the LDAP authentication backend is mounted
                                                      in Vault, e.g: "ldap"
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      SecretRef to a key in a Secret resource containing password for the LDAP
                                                      user used to authenticate with Vault using the LDAP authentication
                                                      method
                                                    '';
                                                  };
                                                  username = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Username is an LDAP username used to authenticate using the LDAP Vault
                                                      authentication method
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              Ldap authenticates with Vault by passing username/password pair using
                                              the LDAP authentication method
                                            '';
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              Name of the vault namespace to authenticate to. This can be different than the namespace your secret is in.
                                              Namespaces is a set of features within Vault Enterprise that allows
                                              Vault environments to support Secure Multi-tenancy. e.g: "ns1".
                                              More about namespaces can be found here https://www.vaultproject.io/docs/enterprise/namespaces
                                              This will default to Vault.Namespace field if set, or empty otherwise
                                            '';
                                          };
                                          tokenSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "TokenSecretRef authenticates with Vault by presenting a token.";
                                          };
                                          userPass = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  path = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Path where the UserPassword authentication backend is mounted
                                                      in Vault, e.g: "userpass"
                                                    '';
                                                  };
                                                  secretRef = mkOption {
                                                    type = (
                                                      types.nullOr (mkTypedSubmodule {
                                                        options = {
                                                          key = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              A key in the referenced Secret.
                                                              Some instances of this field may be defaulted, in others it may be required.
                                                            '';
                                                          };
                                                          name = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = "The name of the Secret resource being referred to.";
                                                          };
                                                          namespace = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              The namespace of the Secret resource being referred to.
                                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    );
                                                    default = null;
                                                    description = ''
                                                      SecretRef to a key in a Secret resource containing password for the
                                                      user used to authenticate with Vault using the UserPass authentication
                                                      method
                                                    '';
                                                  };
                                                  username = mkOption {
                                                    type = types.str;
                                                    description = ''
                                                      Username is a username used to authenticate using the UserPass Vault
                                                      authentication method
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "UserPass authenticates with Vault by passing username/password pair";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "Auth configures how secret-manager authenticates with the Vault server.";
                                  };
                                  caBundle = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      PEM encoded CA bundle used to validate Vault server certificate. Only used
                                      if the Server URL is using HTTPS protocol. This parameter is ignored for
                                      plain HTTP protocol connection. If not set the system root certificates
                                      are used to validate the TLS connection.
                                    '';
                                  };
                                  caProvider = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The key where the CA certificate can be found in the Secret or ConfigMap.";
                                          };
                                          name = mkOption {
                                            type = types.str;
                                            description = "The name of the object located at the provider type.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace the Provider type is in.
                                              Can only be defined when used in a ClusterSecretStore.
                                            '';
                                          };
                                          type = mkOption {
                                            type = (
                                              types.enum [
                                                "Secret"
                                                "ConfigMap"
                                              ]
                                            );
                                            description = "The type of provider to use such as \"Secret\", or \"ConfigMap\".";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "The provider for the CA bundle to use to validate Vault server certificate.";
                                  };
                                  forwardInconsistent = mkOption {
                                    type = (types.nullOr types.bool);
                                    default = null;
                                    description = ''
                                      ForwardInconsistent tells Vault to forward read-after-write requests to the Vault
                                      leader instead of simply retrying within a loop. This can increase performance if
                                      the option is enabled serverside.
                                      https://www.vaultproject.io/docs/configuration/replication#allow_forwarding_via_header
                                    '';
                                  };
                                  headers = mkOption {
                                    type = (types.nullOr (types.attrsOf types.str));
                                    default = null;
                                    description = "Headers to be added in Vault request";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Name of the vault namespace. Namespaces is a set of features within Vault Enterprise that allows
                                      Vault environments to support Secure Multi-tenancy. e.g: "ns1".
                                      More about namespaces can be found here https://www.vaultproject.io/docs/enterprise/namespaces
                                    '';
                                  };
                                  path = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Path is the mount path of the Vault KV backend endpoint, e.g:
                                      "secret". The v2 KV secret engine version specific "/data" path suffix
                                      for fetching secrets from Vault is optional and will be appended
                                      if not present in specified path.
                                    '';
                                  };
                                  readYourWrites = mkOption {
                                    type = (types.nullOr types.bool);
                                    default = null;
                                    description = ''
                                      ReadYourWrites ensures isolated read-after-write semantics by
                                      providing discovered cluster replication states in each request.
                                      More information about eventual consistency in Vault can be found here
                                      https://www.vaultproject.io/docs/enterprise/consistency
                                    '';
                                  };
                                  server = mkOption {
                                    type = types.str;
                                    description = "Server is the connection address for the Vault server, e.g: \"https://vault.example.com:8200\".";
                                  };
                                  tls = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          certSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              CertSecretRef is a certificate added to the transport layer
                                              when communicating with the Vault server.
                                              If no key for the Secret is specified, external-secret will default to 'tls.crt'.
                                            '';
                                          };
                                          keySecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              KeySecretRef to a key in a Secret resource containing client private key
                                              added to the transport layer when communicating with the Vault server.
                                              If no key for the Secret is specified, external-secret will default to 'tls.key'.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      The configuration used for client side related TLS communication, when the Vault server
                                      requires mutual authentication. Only used if the Server URL is using HTTPS protocol.
                                      This parameter is ignored for plain HTTP protocol connection.
                                      It's worth noting this configuration is different from the "TLS certificates auth method",
                                      which is available under the `auth.cert` section.
                                    '';
                                  };
                                  version = mkOption {
                                    type = (
                                      types.nullOr (
                                        types.enum [
                                          "v1"
                                          "v2"
                                        ]
                                      )
                                    );
                                    default = null;
                                    description = ''
                                      Version is the Vault KV secret engine version. This can be either "v1" or
                                      "v2". Version defaults to "v2".
                                    '';
                                  };
                                };
                              }
                            );
                            description = "Vault provider common spec";
                          };
                          resultType = mkOption {
                            type = (
                              types.nullOr (
                                types.enum [
                                  "Data"
                                  "Auth"
                                  "Raw"
                                ]
                              )
                            );
                            default = null;
                            description = ''
                              Result type defines which data is returned from the generator.
                              By default it is the "data" section of the Vault API response.
                              When using e.g. /auth/token/create the "data" section is empty but
                              the "auth" section contains the generated token.
                              Please refer to the vault docs regarding the result data structure.
                              Additionally, accessing the raw response is possibly by using "Raw" result type.
                            '';
                          };
                          retrySettings = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  maxRetries = mkOption {
                                    type = (types.nullOr types.int);
                                    default = null;
                                  };
                                  retryInterval = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "Used to configure http retries if failed";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  webhookSpec = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          body = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "Body";
                          };
                          caBundle = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              PEM encoded CA bundle used to validate webhook server certificate. Only used
                              if the Server URL is using HTTPS protocol. This parameter is ignored for
                              plain HTTP protocol connection. If not set the system root certificates
                              are used to validate the TLS connection.
                            '';
                          };
                          caProvider = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The key where the CA certificate can be found in the Secret or ConfigMap.";
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the object located at the provider type.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The namespace the Provider type is in.";
                                  };
                                  type = mkOption {
                                    type = (
                                      types.enum [
                                        "Secret"
                                        "ConfigMap"
                                      ]
                                    );
                                    description = "The type of provider to use such as \"Secret\", or \"ConfigMap\".";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The provider for the CA bundle to use to validate webhook server certificate.";
                          };
                          headers = mkOption {
                            type = (types.nullOr (types.attrsOf types.str));
                            default = null;
                            description = "Headers";
                          };
                          method = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "Webhook Method";
                          };
                          result = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  jsonPath = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "Json path of return value";
                                  };
                                };
                              }
                            );
                            description = "Result formatting";
                          };
                          secrets = mkOption {
                            type = (
                              types.nullOr (
                                types.listOf (mkTypedSubmodule {
                                  options = {
                                    name = mkOption {
                                      type = types.str;
                                      description = "Name of this secret in templates";
                                    };
                                    secretRef = mkOption {
                                      type = (
                                        mkTypedSubmodule {
                                          options = {
                                            key = mkOption {
                                              type = (types.nullOr types.str);
                                              default = null;
                                              description = "The key where the token is found.";
                                            };
                                            name = mkOption {
                                              type = (types.nullOr types.str);
                                              default = null;
                                              description = "The name of the Secret resource being referred to.";
                                            };
                                          };
                                        }
                                      );
                                      description = "Secret ref to fill in credentials";
                                    };
                                  };
                                })
                              )
                            );
                            default = null;
                            description = ''
                              Secrets to fill in templates
                              These secrets will be passed to the templating function as key value pairs under the given name
                            '';
                          };
                          timeout = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "Timeout";
                          };
                          url = mkOption {
                            type = types.str;
                            description = "Webhook url to call";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "WebhookSpec controls the behavior of the external generator. Any body parameters should be passed to the server through the parameters field.";
                  };
                };
              }
            );
            description = "Generator the spec for this generator, must match the kind.";
          };
          kind = mkOption {
            type = (
              types.enum [
                "ACRAccessToken"
                "ECRAuthorizationToken"
                "Fake"
                "GCRAccessToken"
                "GithubAccessToken"
                "QuayAccessToken"
                "Password"
                "STSSessionToken"
                "UUID"
                "VaultDynamicSecret"
                "Webhook"
                "Grafana"
              ]
            );
            description = "Kind the kind of this generator.";
          };
        };
      }
    );
  };

  ECRAuthorizationToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "ECRAuthorizationToken";
    specType = (
      mkTypedSubmodule {
        options = {
          auth = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  jwt = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          serviceAccountRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  audiences = mkOption {
                                    type = (types.nullOr (types.listOf types.str));
                                    default = null;
                                    description = ''
                                      Audience specifies the `aud` claim for the service account token
                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                      then this audiences will be appended to the list
                                    '';
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the ServiceAccount resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Namespace of the resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "A reference to a ServiceAccount resource.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "Authenticate against AWS using service account tokens.";
                  };
                  secretRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          accessKeyIDSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The AccessKeyID is used for authentication";
                          };
                          secretAccessKeySecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The SecretAccessKey is used for authentication";
                          };
                          sessionTokenSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              The SessionToken used for authentication
                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      AWSAuthSecretRef holds secret references for AWS credentials
                      both AccessKeyID and SecretAccessKey must be defined in order to properly authenticate.
                    '';
                  };
                };
              })
            );
            default = null;
            description = "Auth defines how to authenticate with AWS";
          };
          region = mkOption {
            type = types.str;
            description = "Region specifies the region to operate in.";
          };
          role = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              You can assume a role before making calls to the
              desired AWS service.
            '';
          };
          scope = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              Scope specifies the ECR service scope.
              Valid options are private and public.
            '';
          };
        };
      }
    );
  };

  Fake = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "Fake";
    specType = (
      mkTypedSubmodule {
        options = {
          controller = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              Used to select the correct ESO controller (think: ingress.ingressClassName)
              The ESO controller is instantiated with a specific controller name and filters VDS based on this property
            '';
          };
          data = mkOption {
            type = (types.nullOr (types.attrsOf types.str));
            default = null;
            description = ''
              Data defines the static data returned
              by this generator.
            '';
          };
        };
      }
    );
  };

  GCRAccessToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "GCRAccessToken";
    specType = (
      mkTypedSubmodule {
        options = {
          auth = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  secretRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          secretAccessKeySecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The SecretAccessKey is used for authentication";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                  workloadIdentity = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          clusterLocation = mkOption {
                            type = types.str;
                          };
                          clusterName = mkOption {
                            type = types.str;
                          };
                          clusterProjectID = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                          };
                          serviceAccountRef = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  audiences = mkOption {
                                    type = (types.nullOr (types.listOf types.str));
                                    default = null;
                                    description = ''
                                      Audience specifies the `aud` claim for the service account token
                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                      then this audiences will be appended to the list
                                    '';
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the ServiceAccount resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Namespace of the resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              }
                            );
                            description = "A reference to a ServiceAccount resource.";
                          };
                        };
                      })
                    );
                    default = null;
                  };
                };
              }
            );
            description = "Auth defines the means for authenticating with GCP";
          };
          projectID = mkOption {
            type = types.str;
            description = "ProjectID defines which project to use to authenticate with";
          };
        };
      }
    );
  };

  GeneratorState = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "GeneratorState";
    specType = (
      mkTypedSubmodule {
        options = {
          garbageCollectionDeadline = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              GarbageCollectionDeadline is the time after which the generator state
              will be deleted.
              It is set by the controller which creates the generator state and
              can be set configured by the user.
              If the garbage collection deadline is not set the generator state will not be deleted.
            '';
          };
          resource = mkOption {
            type = types.anything;
            description = ''
              Resource is the generator manifest that produced the state.
              It is a snapshot of the generator manifest at the time the state was produced.
              This manifest will be used to delete the resource. Any configuration that is referenced
              in the manifest should be available at the time of garbage collection. If that is not the case deletion will
              be blocked by a finalizer.
            '';
          };
          state = mkOption {
            type = types.anything;
            description = "State is the state that was produced by the generator implementation.";
          };
        };
      }
    );
  };

  GithubAccessToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "GithubAccessToken";
    specType = (
      mkTypedSubmodule {
        options = {
          appID = mkOption {
            type = types.str;
          };
          auth = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  privateKey = mkOption {
                    type = (
                      mkTypedSubmodule {
                        options = {
                          secretRef = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              }
                            );
                            description = ''
                              A reference to a specific 'key' within a Secret resource.
                              In some instances, `key` is a required field.
                            '';
                          };
                        };
                      }
                    );
                  };
                };
              }
            );
            description = "Auth configures how ESO authenticates with a Github instance.";
          };
          installID = mkOption {
            type = types.str;
          };
          permissions = mkOption {
            type = (types.nullOr (types.attrsOf types.str));
            default = null;
            description = "Map of permissions the token will have. If omitted, defaults to all permissions the GitHub App has.";
          };
          repositories = mkOption {
            type = (types.nullOr (types.listOf types.str));
            default = null;
            description = ''
              List of repositories the token will have access to. If omitted, defaults to all repositories the GitHub App
              is installed to.
            '';
          };
          url = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "URL configures the Github instance URL. Defaults to https://github.com/.";
          };
        };
      }
    );
  };

  Grafana = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "Grafana";
    specType = (
      mkTypedSubmodule {
        options = {
          auth = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  basic = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          password = mkOption {
                            type = (
                              mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The key where the token is found.";
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                };
                              }
                            );
                            description = "A basic auth password used to authenticate against the Grafana instance.";
                          };
                          username = mkOption {
                            type = types.str;
                            description = "A basic auth username used to authenticate against the Grafana instance.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      Basic auth credentials used to authenticate against the Grafana instance.
                      Note: you need a token which has elevated permissions to create service accounts.
                      See here for the documentation on basic roles offered by Grafana:
                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                    '';
                  };
                  token = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          key = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "The key where the token is found.";
                          };
                          name = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "The name of the Secret resource being referred to.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      A service account token used to authenticate against the Grafana instance.
                      Note: you need a token which has elevated permissions to create service accounts.
                      See here for the documentation on basic roles offered by Grafana:
                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                    '';
                  };
                };
              }
            );
            description = ''
              Auth is the authentication configuration to authenticate
              against the Grafana instance.
            '';
          };
          serviceAccount = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Name is the name of the service account that will be created by ESO.";
                  };
                  role = mkOption {
                    type = types.str;
                    description = ''
                      Role is the role of the service account.
                      See here for the documentation on basic roles offered by Grafana:
                      https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/access-control/rbac-fixed-basic-role-definitions/
                    '';
                  };
                };
              }
            );
            description = ''
              ServiceAccount is the configuration for the service account that
              is supposed to be generated by the generator.
            '';
          };
          url = mkOption {
            type = types.str;
            description = "URL is the URL of the Grafana instance.";
          };
        };
      }
    );
  };

  Password = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "Password";
    specType = (
      mkTypedSubmodule {
        options = {
          allowRepeat = mkOption {
            type = types.bool;
            description = "set AllowRepeat to true to allow repeating characters.";
          };
          digits = mkOption {
            type = (types.nullOr types.int);
            default = null;
            description = ''
              Digits specifies the number of digits in the generated
              password. If omitted it defaults to 25% of the length of the password
            '';
          };
          length = mkOption {
            type = types.int;
            description = ''
              Length of the password to be generated.
              Defaults to 24
            '';
          };
          noUpper = mkOption {
            type = types.bool;
            description = "Set NoUpper to disable uppercase characters";
          };
          symbolCharacters = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              SymbolCharacters specifies the special characters that should be used
              in the generated password.
            '';
          };
          symbols = mkOption {
            type = (types.nullOr types.int);
            default = null;
            description = ''
              Symbols specifies the number of symbol characters in the generated
              password. If omitted it defaults to 25% of the length of the password
            '';
          };
        };
      }
    );
  };

  QuayAccessToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "QuayAccessToken";
    specType = (
      mkTypedSubmodule {
        options = {
          robotAccount = mkOption {
            type = types.str;
            description = "Name of the robot account you are federating with";
          };
          serviceAccountRef = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  audiences = mkOption {
                    type = (types.nullOr (types.listOf types.str));
                    default = null;
                    description = ''
                      Audience specifies the `aud` claim for the service account token
                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                      then this audiences will be appended to the list
                    '';
                  };
                  name = mkOption {
                    type = types.str;
                    description = "The name of the ServiceAccount resource being referred to.";
                  };
                  namespace = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      Namespace of the resource being referred to.
                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                    '';
                  };
                };
              }
            );
            description = "Name of the service account you are federating with";
          };
          url = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "URL configures the Quay instance URL. Defaults to quay.io.";
          };
        };
      }
    );
  };

  STSSessionToken = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "STSSessionToken";
    specType = (
      mkTypedSubmodule {
        options = {
          auth = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  jwt = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          serviceAccountRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  audiences = mkOption {
                                    type = (types.nullOr (types.listOf types.str));
                                    default = null;
                                    description = ''
                                      Audience specifies the `aud` claim for the service account token
                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                      then this audiences will be appended to the list
                                    '';
                                  };
                                  name = mkOption {
                                    type = types.str;
                                    description = "The name of the ServiceAccount resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Namespace of the resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "A reference to a ServiceAccount resource.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "Authenticate against AWS using service account tokens.";
                  };
                  secretRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          accessKeyIDSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The AccessKeyID is used for authentication";
                          };
                          secretAccessKeySecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "The SecretAccessKey is used for authentication";
                          };
                          sessionTokenSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              The SessionToken used for authentication
                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      AWSAuthSecretRef holds secret references for AWS credentials
                      both AccessKeyID and SecretAccessKey must be defined in order to properly authenticate.
                    '';
                  };
                };
              })
            );
            default = null;
            description = "Auth defines how to authenticate with AWS";
          };
          region = mkOption {
            type = types.str;
            description = "Region specifies the region to operate in.";
          };
          requestParameters = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  serialNumber = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      SerialNumber is the identification number of the MFA device that is associated with the IAM user who is making
                      the GetSessionToken call.
                      Possible values: hardware device (such as GAHT12345678) or an Amazon Resource Name (ARN) for a virtual device
                      (such as arn:aws:iam::123456789012:mfa/user)
                    '';
                  };
                  sessionDuration = mkOption {
                    type = (types.nullOr types.int);
                    default = null;
                    description = ''
                      SessionDuration The duration, in seconds, that the credentials should remain valid. Acceptable durations for
                      IAM user sessions range from 900 seconds (15 minutes) to 129,600 seconds (36 hours), with 43,200 seconds
                      (12 hours) as the default.
                    '';
                  };
                  tokenCode = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "TokenCode is the value provided by the MFA device, if MFA is required.";
                  };
                };
              })
            );
            default = null;
            description = "RequestParameters contains parameters that can be passed to the STS service.";
          };
          role = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              You can assume a role before making calls to the
              desired AWS service.
            '';
          };
        };
      }
    );
  };

  UUID = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "UUID";
    specType = types.attrs;
  };

  VaultDynamicSecret = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "VaultDynamicSecret";
    specType = (
      mkTypedSubmodule {
        options = {
          allowEmptyResponse = mkOption {
            type = (types.nullOr types.bool);
            default = null;
            description = "Do not fail if no secrets are found. Useful for requests where no data is expected.";
          };
          controller = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              Used to select the correct ESO controller (think: ingress.ingressClassName)
              The ESO controller is instantiated with a specific controller name and filters VDS based on this property
            '';
          };
          method = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "Vault API method to use (GET/POST/other)";
          };
          parameters = mkOption {
            type = (types.nullOr types.anything);
            default = null;
            description = "Parameters to pass to Vault write (for non-GET methods)";
          };
          path = mkOption {
            type = types.str;
            description = "Vault path to obtain the dynamic secret from";
          };
          provider = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  auth = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          appRole = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  path = mkOption {
                                    type = types.str;
                                    description = ''
                                      Path where the App Role authentication backend is mounted
                                      in Vault, e.g: "approle"
                                    '';
                                  };
                                  roleId = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      RoleID configured in the App Role authentication backend when setting
                                      up the authentication backend in Vault.
                                    '';
                                  };
                                  roleRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Reference to a key in a Secret that contains the App Role ID used
                                      to authenticate with Vault.
                                      The `key` field must be specified and denotes which entry within the Secret
                                      resource is used as the app role id.
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      }
                                    );
                                    description = ''
                                      Reference to a key in a Secret that contains the App Role secret used
                                      to authenticate with Vault.
                                      The `key` field must be specified and denotes which entry within the Secret
                                      resource is used as the app role secret.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              AppRole authenticates with Vault using the App Role auth mechanism,
                              with the role and secret stored in a Kubernetes Secret resource.
                            '';
                          };
                          cert = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  clientCert = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      ClientCert is a certificate to authenticate using the Cert Vault
                                      authentication method
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      SecretRef to a key in a Secret resource containing client private key to
                                      authenticate with Vault using the Cert authentication method
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Cert authenticates with TLS Certificates by passing client certificate, private key and ca certificate
                              Cert authentication method
                            '';
                          };
                          iam = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  externalID = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "AWS External ID set on assumed IAM roles";
                                  };
                                  jwt = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          serviceAccountRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "A reference to a ServiceAccount resource.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "Specify a service account with IRSA enabled";
                                  };
                                  path = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "Path where the AWS auth method is enabled in Vault, e.g: \"aws\"";
                                  };
                                  region = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "AWS region";
                                  };
                                  role = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "This is the AWS role to be assumed before talking to vault";
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          accessKeyIDSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The AccessKeyID is used for authentication";
                                          };
                                          secretAccessKeySecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = "The SecretAccessKey is used for authentication";
                                          };
                                          sessionTokenSecretRef = mkOption {
                                            type = (
                                              types.nullOr (mkTypedSubmodule {
                                                options = {
                                                  key = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      A key in the referenced Secret.
                                                      Some instances of this field may be defaulted, in others it may be required.
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = "The name of the Secret resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      The namespace of the Secret resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              })
                                            );
                                            default = null;
                                            description = ''
                                              The SessionToken used for authentication
                                              This must be defined if AccessKeyID and SecretAccessKey are temporary credentials
                                              see: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = "Specify credentials in a Secret object";
                                  };
                                  vaultAwsIamServerID = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "X-Vault-AWS-IAM-Server-ID is an additional header used by Vault IAM auth method to mitigate against different types of replay attacks. More details here: https://developer.hashicorp.com/vault/docs/auth/aws";
                                  };
                                  vaultRole = mkOption {
                                    type = types.str;
                                    description = "Vault Role. In vault, a role describes an identity with a set of permissions, groups, or policies you want to attach a user of the secrets engine";
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Iam authenticates with vault by passing a special AWS request signed with AWS IAM credentials
                              AWS IAM authentication method
                            '';
                          };
                          jwt = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  kubernetesServiceAccountToken = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          audiences = mkOption {
                                            type = (types.nullOr (types.listOf types.str));
                                            default = null;
                                            description = ''
                                              Optional audiences field that will be used to request a temporary Kubernetes service
                                              account token for the service account referenced by `serviceAccountRef`.
                                              Defaults to a single audience `vault` it not specified.
                                              Deprecated: use serviceAccountRef.Audiences instead
                                            '';
                                          };
                                          expirationSeconds = mkOption {
                                            type = (types.nullOr types.int);
                                            default = null;
                                            description = ''
                                              Optional expiration time in seconds that will be used to request a temporary
                                              Kubernetes service account token for the service account referenced by
                                              `serviceAccountRef`.
                                              Deprecated: this will be removed in the future.
                                              Defaults to 10 minutes.
                                            '';
                                          };
                                          serviceAccountRef = mkOption {
                                            type = (
                                              mkTypedSubmodule {
                                                options = {
                                                  audiences = mkOption {
                                                    type = (types.nullOr (types.listOf types.str));
                                                    default = null;
                                                    description = ''
                                                      Audience specifies the `aud` claim for the service account token
                                                      If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                                      then this audiences will be appended to the list
                                                    '';
                                                  };
                                                  name = mkOption {
                                                    type = types.str;
                                                    description = "The name of the ServiceAccount resource being referred to.";
                                                  };
                                                  namespace = mkOption {
                                                    type = (types.nullOr types.str);
                                                    default = null;
                                                    description = ''
                                                      Namespace of the resource being referred to.
                                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                                    '';
                                                  };
                                                };
                                              }
                                            );
                                            description = "Service account field containing the name of a kubernetes ServiceAccount.";
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Optional ServiceAccountToken specifies the Kubernetes service account for which to request
                                      a token for with the `TokenRequest` API.
                                    '';
                                  };
                                  path = mkOption {
                                    type = types.str;
                                    description = ''
                                      Path where the JWT authentication backend is mounted
                                      in Vault, e.g: "jwt"
                                    '';
                                  };
                                  role = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      Role is a JWT role to authenticate using the JWT/OIDC Vault
                                      authentication method
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Optional SecretRef that refers to a key in a Secret resource containing JWT token to
                                      authenticate with Vault using the JWT/OIDC authentication method.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Jwt authenticates with Vault by passing role and JWT token using the
                              JWT/OIDC authentication method
                            '';
                          };
                          kubernetes = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  mountPath = mkOption {
                                    type = types.str;
                                    description = ''
                                      Path where the Kubernetes authentication backend is mounted in Vault, e.g:
                                      "kubernetes"
                                    '';
                                  };
                                  role = mkOption {
                                    type = types.str;
                                    description = ''
                                      A required field containing the Vault Role to assume. A Role binds a
                                      Kubernetes ServiceAccount with a set of Vault policies.
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Optional secret field containing a Kubernetes ServiceAccount JWT used
                                      for authenticating with Vault. If a name is specified without a key,
                                      `token` is the default. If one is not specified, the one bound to
                                      the controller will be used.
                                    '';
                                  };
                                  serviceAccountRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          audiences = mkOption {
                                            type = (types.nullOr (types.listOf types.str));
                                            default = null;
                                            description = ''
                                              Audience specifies the `aud` claim for the service account token
                                              If the service account uses a well-known annotation for e.g. IRSA or GCP Workload Identity
                                              then this audiences will be appended to the list
                                            '';
                                          };
                                          name = mkOption {
                                            type = types.str;
                                            description = "The name of the ServiceAccount resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              Namespace of the resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      Optional service account field containing the name of a kubernetes ServiceAccount.
                                      If the service account is specified, the service account secret token JWT will be used
                                      for authenticating with Vault. If the service account selector is not supplied,
                                      the secretRef will be used instead.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Kubernetes authenticates with Vault by passing the ServiceAccount
                              token stored in the named Secret resource to the Vault server.
                            '';
                          };
                          ldap = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  path = mkOption {
                                    type = types.str;
                                    description = ''
                                      Path where the LDAP authentication backend is mounted
                                      in Vault, e.g: "ldap"
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      SecretRef to a key in a Secret resource containing password for the LDAP
                                      user used to authenticate with Vault using the LDAP authentication
                                      method
                                    '';
                                  };
                                  username = mkOption {
                                    type = types.str;
                                    description = ''
                                      Username is an LDAP username used to authenticate using the LDAP Vault
                                      authentication method
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              Ldap authenticates with Vault by passing username/password pair using
                              the LDAP authentication method
                            '';
                          };
                          namespace = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              Name of the vault namespace to authenticate to. This can be different than the namespace your secret is in.
                              Namespaces is a set of features within Vault Enterprise that allows
                              Vault environments to support Secure Multi-tenancy. e.g: "ns1".
                              More about namespaces can be found here https://www.vaultproject.io/docs/enterprise/namespaces
                              This will default to Vault.Namespace field if set, or empty otherwise
                            '';
                          };
                          tokenSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "TokenSecretRef authenticates with Vault by presenting a token.";
                          };
                          userPass = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  path = mkOption {
                                    type = types.str;
                                    description = ''
                                      Path where the UserPassword authentication backend is mounted
                                      in Vault, e.g: "userpass"
                                    '';
                                  };
                                  secretRef = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          key = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              A key in the referenced Secret.
                                              Some instances of this field may be defaulted, in others it may be required.
                                            '';
                                          };
                                          name = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "The name of the Secret resource being referred to.";
                                          };
                                          namespace = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = ''
                                              The namespace of the Secret resource being referred to.
                                              Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      SecretRef to a key in a Secret resource containing password for the
                                      user used to authenticate with Vault using the UserPass authentication
                                      method
                                    '';
                                  };
                                  username = mkOption {
                                    type = types.str;
                                    description = ''
                                      Username is a username used to authenticate using the UserPass Vault
                                      authentication method
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "UserPass authenticates with Vault by passing username/password pair";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "Auth configures how secret-manager authenticates with the Vault server.";
                  };
                  caBundle = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      PEM encoded CA bundle used to validate Vault server certificate. Only used
                      if the Server URL is using HTTPS protocol. This parameter is ignored for
                      plain HTTP protocol connection. If not set the system root certificates
                      are used to validate the TLS connection.
                    '';
                  };
                  caProvider = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          key = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = "The key where the CA certificate can be found in the Secret or ConfigMap.";
                          };
                          name = mkOption {
                            type = types.str;
                            description = "The name of the object located at the provider type.";
                          };
                          namespace = mkOption {
                            type = (types.nullOr types.str);
                            default = null;
                            description = ''
                              The namespace the Provider type is in.
                              Can only be defined when used in a ClusterSecretStore.
                            '';
                          };
                          type = mkOption {
                            type = (
                              types.enum [
                                "Secret"
                                "ConfigMap"
                              ]
                            );
                            description = "The type of provider to use such as \"Secret\", or \"ConfigMap\".";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "The provider for the CA bundle to use to validate Vault server certificate.";
                  };
                  forwardInconsistent = mkOption {
                    type = (types.nullOr types.bool);
                    default = null;
                    description = ''
                      ForwardInconsistent tells Vault to forward read-after-write requests to the Vault
                      leader instead of simply retrying within a loop. This can increase performance if
                      the option is enabled serverside.
                      https://www.vaultproject.io/docs/configuration/replication#allow_forwarding_via_header
                    '';
                  };
                  headers = mkOption {
                    type = (types.nullOr (types.attrsOf types.str));
                    default = null;
                    description = "Headers to be added in Vault request";
                  };
                  namespace = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      Name of the vault namespace. Namespaces is a set of features within Vault Enterprise that allows
                      Vault environments to support Secure Multi-tenancy. e.g: "ns1".
                      More about namespaces can be found here https://www.vaultproject.io/docs/enterprise/namespaces
                    '';
                  };
                  path = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      Path is the mount path of the Vault KV backend endpoint, e.g:
                      "secret". The v2 KV secret engine version specific "/data" path suffix
                      for fetching secrets from Vault is optional and will be appended
                      if not present in specified path.
                    '';
                  };
                  readYourWrites = mkOption {
                    type = (types.nullOr types.bool);
                    default = null;
                    description = ''
                      ReadYourWrites ensures isolated read-after-write semantics by
                      providing discovered cluster replication states in each request.
                      More information about eventual consistency in Vault can be found here
                      https://www.vaultproject.io/docs/enterprise/consistency
                    '';
                  };
                  server = mkOption {
                    type = types.str;
                    description = "Server is the connection address for the Vault server, e.g: \"https://vault.example.com:8200\".";
                  };
                  tls = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          certSecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              CertSecretRef is a certificate added to the transport layer
                              when communicating with the Vault server.
                              If no key for the Secret is specified, external-secret will default to 'tls.crt'.
                            '';
                          };
                          keySecretRef = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  key = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      A key in the referenced Secret.
                                      Some instances of this field may be defaulted, in others it may be required.
                                    '';
                                  };
                                  name = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = "The name of the Secret resource being referred to.";
                                  };
                                  namespace = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      The namespace of the Secret resource being referred to.
                                      Ignored if referent is not cluster-scoped, otherwise defaults to the namespace of the referent.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = ''
                              KeySecretRef to a key in a Secret resource containing client private key
                              added to the transport layer when communicating with the Vault server.
                              If no key for the Secret is specified, external-secret will default to 'tls.key'.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      The configuration used for client side related TLS communication, when the Vault server
                      requires mutual authentication. Only used if the Server URL is using HTTPS protocol.
                      This parameter is ignored for plain HTTP protocol connection.
                      It's worth noting this configuration is different from the "TLS certificates auth method",
                      which is available under the `auth.cert` section.
                    '';
                  };
                  version = mkOption {
                    type = (
                      types.nullOr (
                        types.enum [
                          "v1"
                          "v2"
                        ]
                      )
                    );
                    default = null;
                    description = ''
                      Version is the Vault KV secret engine version. This can be either "v1" or
                      "v2". Version defaults to "v2".
                    '';
                  };
                };
              }
            );
            description = "Vault provider common spec";
          };
          resultType = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Data"
                  "Auth"
                  "Raw"
                ]
              )
            );
            default = null;
            description = ''
              Result type defines which data is returned from the generator.
              By default it is the "data" section of the Vault API response.
              When using e.g. /auth/token/create the "data" section is empty but
              the "auth" section contains the generated token.
              Please refer to the vault docs regarding the result data structure.
              Additionally, accessing the raw response is possibly by using "Raw" result type.
            '';
          };
          retrySettings = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  maxRetries = mkOption {
                    type = (types.nullOr types.int);
                    default = null;
                  };
                  retryInterval = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                  };
                };
              })
            );
            default = null;
            description = "Used to configure http retries if failed";
          };
        };
      }
    );
  };

  Webhook = mkResource {
    apiVersion = "generators.external-secrets.io/v1alpha1";
    kind = "Webhook";
    specType = (
      mkTypedSubmodule {
        options = {
          body = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "Body";
          };
          caBundle = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              PEM encoded CA bundle used to validate webhook server certificate. Only used
              if the Server URL is using HTTPS protocol. This parameter is ignored for
              plain HTTP protocol connection. If not set the system root certificates
              are used to validate the TLS connection.
            '';
          };
          caProvider = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  key = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "The key where the CA certificate can be found in the Secret or ConfigMap.";
                  };
                  name = mkOption {
                    type = types.str;
                    description = "The name of the object located at the provider type.";
                  };
                  namespace = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "The namespace the Provider type is in.";
                  };
                  type = mkOption {
                    type = (
                      types.enum [
                        "Secret"
                        "ConfigMap"
                      ]
                    );
                    description = "The type of provider to use such as \"Secret\", or \"ConfigMap\".";
                  };
                };
              })
            );
            default = null;
            description = "The provider for the CA bundle to use to validate webhook server certificate.";
          };
          headers = mkOption {
            type = (types.nullOr (types.attrsOf types.str));
            default = null;
            description = "Headers";
          };
          method = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "Webhook Method";
          };
          result = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  jsonPath = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "Json path of return value";
                  };
                };
              }
            );
            description = "Result formatting";
          };
          secrets = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    name = mkOption {
                      type = types.str;
                      description = "Name of this secret in templates";
                    };
                    secretRef = mkOption {
                      type = (
                        mkTypedSubmodule {
                          options = {
                            key = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = "The key where the token is found.";
                            };
                            name = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = "The name of the Secret resource being referred to.";
                            };
                          };
                        }
                      );
                      description = "Secret ref to fill in credentials";
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              Secrets to fill in templates
              These secrets will be passed to the templating function as key value pairs under the given name
            '';
          };
          timeout = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "Timeout";
          };
          url = mkOption {
            type = types.str;
            description = "Webhook url to call";
          };
        };
      }
    );
  };

}
