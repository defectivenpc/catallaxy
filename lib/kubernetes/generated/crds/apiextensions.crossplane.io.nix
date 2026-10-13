{ lib, k8sTypes }:

let
  inherit (lib) mkOption types;
  inherit (k8sTypes) mkTypedSubmodule mkResource;
in
{
  CompositeResourceDefinition = mkResource {
    apiVersion = "apiextensions.crossplane.io/v1";
    kind = "CompositeResourceDefinition";
    specType = (
      mkTypedSubmodule {
        options = {
          claimNames = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  categories = mkOption {
                    type = (types.nullOr (types.listOf types.str));
                    default = null;
                    description = ''
                      categories is a list of grouped resources this custom resource belongs to (e.g. 'all').
                      This is published in API discovery documents, and used by clients to support invocations like
                      `kubectl get all`.
                    '';
                  };
                  kind = mkOption {
                    type = types.str;
                    description = ''
                      kind is the serialized kind of the resource. It is normally CamelCase and singular.
                      Custom resource instances will use this value as the `kind` attribute in API calls.
                    '';
                  };
                  listKind = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "listKind is the serialized kind of the list for this resource. Defaults to \"`kind`List\".";
                  };
                  plural = mkOption {
                    type = types.str;
                    description = ''
                      plural is the plural name of the resource to serve.
                      The custom resources are served under `/apis/<group>/<version>/.../<plural>`.
                      Must match the name of the CustomResourceDefinition (in the form `<names.plural>.<group>`).
                      Must be all lowercase.
                    '';
                  };
                  shortNames = mkOption {
                    type = (types.nullOr (types.listOf types.str));
                    default = null;
                    description = ''
                      shortNames are short names for the resource, exposed in API discovery documents,
                      and used by clients to support invocations like `kubectl get <shortname>`.
                      It must be all lowercase.
                    '';
                  };
                  singular = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "singular is the singular name of the resource. It must be all lowercase. Defaults to lowercased `kind`.";
                  };
                };
              })
            );
            default = null;
            description = ''
              ClaimNames specifies the names of an optional composite resource claim.
              When claim names are specified Crossplane will create a namespaced
              'composite resource claim' CRD that corresponds to the defined composite
              resource. This composite resource claim acts as a namespaced proxy for
              the composite resource; creating, updating, or deleting the claim will
              create, update, or delete a corresponding composite resource. You may add
              claim names to an existing CompositeResourceDefinition, but they cannot
              be changed or removed once they have been set.
            '';
          };
          connectionSecretKeys = mkOption {
            type = (types.nullOr (types.listOf types.str));
            default = null;
            description = ''
              ConnectionSecretKeys is the list of keys that will be exposed to the end
              user of the defined kind.
              If the list is empty, all keys will be published.
            '';
          };
          conversion = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  strategy = mkOption {
                    type = types.str;
                    description = ''
                      strategy specifies how custom resources are converted between versions. Allowed values are:
                      - `"None"`: The converter only change the apiVersion and would not touch any other field in the custom resource.
                      - `"Webhook"`: API Server will call to an external webhook to do the conversion. Additional information
                        is needed for this option. This requires spec.preserveUnknownFields to be false, and spec.conversion.webhook to be set.
                    '';
                  };
                  webhook = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          clientConfig = mkOption {
                            type = (
                              types.nullOr (mkTypedSubmodule {
                                options = {
                                  caBundle = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      caBundle is a PEM encoded CA bundle which will be used to validate the webhook's server certificate.
                                      If unspecified, system trust roots on the apiserver are used.
                                    '';
                                  };
                                  service = mkOption {
                                    type = (
                                      types.nullOr (mkTypedSubmodule {
                                        options = {
                                          name = mkOption {
                                            type = types.str;
                                            description = ''
                                              name is the name of the service.
                                              Required
                                            '';
                                          };
                                          namespace = mkOption {
                                            type = types.str;
                                            description = ''
                                              namespace is the namespace of the service.
                                              Required
                                            '';
                                          };
                                          path = mkOption {
                                            type = (types.nullOr types.str);
                                            default = null;
                                            description = "path is an optional URL path at which the webhook will be contacted.";
                                          };
                                          port = mkOption {
                                            type = (types.nullOr types.int);
                                            default = null;
                                            description = ''
                                              port is an optional service port at which the webhook will be contacted.
                                              `port` should be a valid port number (1-65535, inclusive).
                                              Defaults to 443 for backward compatibility.
                                            '';
                                          };
                                        };
                                      })
                                    );
                                    default = null;
                                    description = ''
                                      service is a reference to the service for this webhook. Either
                                      service or url must be specified.

                                      If the webhook is running within the cluster, then you should use `service`.
                                    '';
                                  };
                                  url = mkOption {
                                    type = (types.nullOr types.str);
                                    default = null;
                                    description = ''
                                      url gives the location of the webhook, in standard URL form
                                      (`scheme://host:port/path`). Exactly one of `url` or `service`
                                      must be specified.

                                      The `host` should not refer to a service running in the cluster; use
                                      the `service` field instead. The host might be resolved via external
                                      DNS in some apiservers (e.g., `kube-apiserver` cannot resolve
                                      in-cluster DNS as that would be a layering violation). `host` may
                                      also be an IP address.

                                      Please note that using `localhost` or `127.0.0.1` as a `host` is
                                      risky unless you take great care to run this webhook on all hosts
                                      which run an apiserver which might need to make calls to this
                                      webhook. Such installs are likely to be non-portable, i.e., not easy
                                      to turn up in a new cluster.

                                      The scheme must be "https"; the URL must begin with "https://".

                                      A path is optional, and if present may be any string permissible in
                                      a URL. You may use the path to pass an arbitrary string to the
                                      webhook, for example, a cluster identifier.

                                      Attempting to use a user or basic auth e.g. "user:password@" is not
                                      allowed. Fragments ("#...") and query parameters ("?...") are not
                                      allowed, either.
                                    '';
                                  };
                                };
                              })
                            );
                            default = null;
                            description = "clientConfig is the instructions for how to call the webhook if strategy is `Webhook`.";
                          };
                          conversionReviewVersions = mkOption {
                            type = ((types.listOf types.str) // { emptyValue = { }; });
                            description = ''
                              conversionReviewVersions is an ordered list of preferred `ConversionReview`
                              versions the Webhook expects. The API server will use the first version in
                              the list which it supports. If none of the versions specified in this list
                              are supported by API server, conversion will fail for the custom resource.
                              If a persisted Webhook configuration specifies allowed versions and does not
                              include any versions known to the API Server, calls to the webhook will fail.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = "webhook describes how to call the conversion webhook. Required when `strategy` is set to `\"Webhook\"`.";
                  };
                };
              })
            );
            default = null;
            description = "Conversion defines all conversion settings for the defined Composite resource.";
          };
          defaultCompositeDeletePolicy = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Background"
                  "Foreground"
                ]
              )
            );
            default = null;
            description = ''
              DefaultCompositeDeletePolicy is the policy used when deleting the Composite
              that is associated with the Claim if no policy has been specified.
            '';
          };
          defaultCompositionRef = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Name of the Composition.";
                  };
                };
              })
            );
            default = null;
            description = ''
              DefaultCompositionRef refers to the Composition resource that will be used
              in case no composition selector is given.
            '';
          };
          defaultCompositionUpdatePolicy = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Automatic"
                  "Manual"
                ]
              )
            );
            default = null;
            description = ''
              DefaultCompositionUpdatePolicy is the policy used when updating composites after a new
              Composition Revision has been created if no policy has been specified on the composite.
            '';
          };
          enforcedCompositionRef = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Name of the Composition.";
                  };
                };
              })
            );
            default = null;
            description = ''
              EnforcedCompositionRef refers to the Composition resource that will be used
              by all composite instances whose schema is defined by this definition.
            '';
          };
          group = mkOption {
            type = types.str;
            description = ''
              Group specifies the API group of the defined composite resource.
              Composite resources are served under `/apis/<group>/...`. Must match the
              name of the XRD (in the form `<names.plural>.<group>`).
            '';
          };
          metadata = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  annotations = mkOption {
                    type = (types.nullOr (types.attrsOf types.str));
                    default = null;
                    description = ''
                      Annotations is an unstructured key value map stored with a resource that may be
                      set by external tools to store and retrieve arbitrary metadata. They are not
                      queryable and should be preserved when modifying objects.
                      More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations
                    '';
                  };
                  labels = mkOption {
                    type = (types.nullOr (types.attrsOf types.str));
                    default = null;
                    description = ''
                      Map of string keys and values that can be used to organize and categorize
                      (scope and select) objects. May match selectors of replication controllers
                      More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels
                      and services.
                      These labels are added to the composite resource and claim CRD's in addition
                      to any labels defined by `CompositionResourceDefinition` `metadata.labels`.
                    '';
                  };
                };
              })
            );
            default = null;
            description = "Metadata specifies the desired metadata for the defined composite resource and claim CRD's.";
          };
          names = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  categories = mkOption {
                    type = (types.nullOr (types.listOf types.str));
                    default = null;
                    description = ''
                      categories is a list of grouped resources this custom resource belongs to (e.g. 'all').
                      This is published in API discovery documents, and used by clients to support invocations like
                      `kubectl get all`.
                    '';
                  };
                  kind = mkOption {
                    type = types.str;
                    description = ''
                      kind is the serialized kind of the resource. It is normally CamelCase and singular.
                      Custom resource instances will use this value as the `kind` attribute in API calls.
                    '';
                  };
                  listKind = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "listKind is the serialized kind of the list for this resource. Defaults to \"`kind`List\".";
                  };
                  plural = mkOption {
                    type = types.str;
                    description = ''
                      plural is the plural name of the resource to serve.
                      The custom resources are served under `/apis/<group>/<version>/.../<plural>`.
                      Must match the name of the CustomResourceDefinition (in the form `<names.plural>.<group>`).
                      Must be all lowercase.
                    '';
                  };
                  shortNames = mkOption {
                    type = (types.nullOr (types.listOf types.str));
                    default = null;
                    description = ''
                      shortNames are short names for the resource, exposed in API discovery documents,
                      and used by clients to support invocations like `kubectl get <shortname>`.
                      It must be all lowercase.
                    '';
                  };
                  singular = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "singular is the singular name of the resource. It must be all lowercase. Defaults to lowercased `kind`.";
                  };
                };
              }
            );
            description = ''
              Names specifies the resource and kind names of the defined composite
              resource.
            '';
          };
          versions = mkOption {
            type = (
              (types.listOf (mkTypedSubmodule {
                options = {
                  additionalPrinterColumns = mkOption {
                    type = (
                      types.nullOr (
                        types.listOf (mkTypedSubmodule {
                          options = {
                            description = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = "description is a human readable description of this column.";
                            };
                            format = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = ''
                                format is an optional OpenAPI type definition for this column. The 'name' format is applied
                                to the primary identifier column to assist in clients identifying column is the resource name.
                                See https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md#data-types for details.
                              '';
                            };
                            jsonPath = mkOption {
                              type = types.str;
                              description = ''
                                jsonPath is a simple JSON path (i.e. with array notation) which is evaluated against
                                each custom resource to produce the value for this column.
                              '';
                            };
                            name = mkOption {
                              type = types.str;
                              description = "name is a human readable name for the column.";
                            };
                            priority = mkOption {
                              type = (types.nullOr types.int);
                              default = null;
                              description = ''
                                priority is an integer defining the relative importance of this column compared to others. Lower
                                numbers are considered higher priority. Columns that may be omitted in limited space scenarios
                                should be given a priority greater than 0.
                              '';
                            };
                            type = mkOption {
                              type = types.str;
                              description = ''
                                type is an OpenAPI type definition for this column.
                                See https://github.com/OAI/OpenAPI-Specification/blob/master/versions/2.0.md#data-types for details.
                              '';
                            };
                          };
                        })
                      )
                    );
                    default = null;
                    description = ''
                      AdditionalPrinterColumns specifies additional columns returned in Table
                      output. If no columns are specified, a single column displaying the age
                      of the custom resource is used. See the following link for details:
                      https://kubernetes.io/docs/reference/using-api/api-concepts/#receiving-resources-as-tables
                    '';
                  };
                  deprecated = mkOption {
                    type = (types.nullOr types.bool);
                    default = null;
                    description = ''
                      The deprecated field specifies that this version is deprecated and should
                      not be used.
                    '';
                  };
                  deprecationWarning = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      DeprecationWarning specifies the message that should be shown to the user
                      when using this version.
                    '';
                  };
                  name = mkOption {
                    type = types.str;
                    description = ''
                      Name of this version, e.g. “v1”, “v2beta1”, etc. Composite resources are
                      served under this version at `/apis/<group>/<version>/...` if `served` is
                      true.
                    '';
                  };
                  referenceable = mkOption {
                    type = types.bool;
                    description = ''
                      Referenceable specifies that this version may be referenced by a
                      Composition in order to configure which resources an XR may be composed
                      of. Exactly one version must be marked as referenceable; all Compositions
                      must target only the referenceable version. The referenceable version
                      must be served. It's mapped to the CRD's `spec.versions[*].storage` field.
                    '';
                  };
                  schema = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          openAPIV3Schema = mkOption {
                            type = (types.nullOr types.attrs);
                            default = null;
                            description = ''
                              OpenAPIV3Schema is the OpenAPI v3 schema to use for validation and
                              pruning.
                            '';
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      Schema describes the schema used for validation, pruning, and defaulting
                      of this version of the defined composite resource. Fields required by all
                      composite resources will be injected into this schema automatically, and
                      will override equivalently named fields in this schema. Omitting this
                      schema results in a schema that contains only the fields required by all
                      composite resources.
                    '';
                  };
                  served = mkOption {
                    type = types.bool;
                    description = "Served specifies that this version should be served via REST APIs.";
                  };
                };
              }))
              // {
                emptyValue = { };
              }
            );
            description = ''
              Versions is the list of all API versions of the defined composite
              resource. Version names are used to compute the order in which served
              versions are listed in API discovery. If the version string is
              "kube-like", it will sort above non "kube-like" version strings, which
              are ordered lexicographically. "Kube-like" versions start with a "v",
              then are followed by a number (the major version), then optionally the
              string "alpha" or "beta" and another number (the minor version). These
              are sorted first by GA > beta > alpha (where GA is a version with no
              suffix such as beta or alpha), and then by comparing major version, then
              minor version. An example sorted list of versions: v10, v2, v1, v11beta2,
              v10beta3, v3beta1, v12alpha1, v11alpha2, foo1, foo10.
            '';
          };
        };
      }
    );
  };

  CompositionRevision = mkResource {
    apiVersion = "apiextensions.crossplane.io/v1";
    kind = "CompositionRevision";
    specType = (
      mkTypedSubmodule {
        options = {
          compositeTypeRef = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  apiVersion = mkOption {
                    type = types.str;
                    description = "APIVersion of the type.";
                  };
                  kind = mkOption {
                    type = types.str;
                    description = "Kind of the type.";
                  };
                };
              }
            );
            description = ''
              CompositeTypeRef specifies the type of composite resource that this
              composition is compatible with.
            '';
          };
          mode = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Resources"
                  "Pipeline"
                ]
              )
            );
            default = null;
            description = ''
              Mode controls what type or "mode" of Composition will be used.

              "Pipeline" indicates that a Composition specifies a pipeline of
              Composition Functions, each of which is responsible for producing
              composed resources that Crossplane should create or update.

              "Resources" indicates that a Composition uses what is commonly referred
              to as "Patch & Transform" or P&T composition. This mode of Composition
              uses an array of resources, each a template for a composed resource.

              All Compositions should use Pipeline mode. Resources mode is deprecated.
              Resources mode won't be removed in Crossplane 1.x, and will remain the
              default to avoid breaking legacy Compositions. However, it's no longer
              accepting new features, and only accepting security related bug fixes.
            '';
          };
          patchSets = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    name = mkOption {
                      type = types.str;
                      description = "Name of this PatchSet.";
                    };
                    patches = mkOption {
                      type = (
                        (types.listOf (mkTypedSubmodule {
                          options = {
                            combine = mkOption {
                              type = (
                                types.nullOr (mkTypedSubmodule {
                                  options = {
                                    strategy = mkOption {
                                      type = (types.enum [ "string" ]);
                                      description = ''
                                        Strategy defines the strategy to use to combine the input variable values.
                                        Currently only string is supported.
                                      '';
                                    };
                                    string = mkOption {
                                      type = (
                                        types.nullOr (mkTypedSubmodule {
                                          options = {
                                            fmt = mkOption {
                                              type = types.str;
                                              description = ''
                                                Format the input using a Go format string. See
                                                https://golang.org/pkg/fmt/ for details.
                                              '';
                                            };
                                          };
                                        })
                                      );
                                      default = null;
                                      description = ''
                                        String declares that input variables should be combined into a single
                                        string, using the relevant settings for formatting purposes.
                                      '';
                                    };
                                    variables = mkOption {
                                      type = (
                                        (types.listOf (mkTypedSubmodule {
                                          options = {
                                            fromFieldPath = mkOption {
                                              type = types.str;
                                              description = ''
                                                FromFieldPath is the path of the field on the source whose value is
                                                to be used as input.
                                              '';
                                            };
                                          };
                                        }))
                                        // {
                                          emptyValue = { };
                                        }
                                      );
                                      description = ''
                                        Variables are the list of variables whose values will be retrieved and
                                        combined.
                                      '';
                                    };
                                  };
                                })
                              );
                              default = null;
                              description = ''
                                Combine is the patch configuration for a CombineFromComposite or
                                CombineToComposite patch.
                              '';
                            };
                            fromFieldPath = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = ''
                                FromFieldPath is the path of the field on the resource whose value is
                                to be used as input. Required when type is FromCompositeFieldPath or
                                ToCompositeFieldPath.
                              '';
                            };
                            patchSetName = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = "PatchSetName to include patches from. Required when type is PatchSet.";
                            };
                            policy = mkOption {
                              type = (
                                types.nullOr (mkTypedSubmodule {
                                  options = {
                                    fromFieldPath = mkOption {
                                      type = (
                                        types.nullOr (
                                          types.enum [
                                            "Optional"
                                            "Required"
                                          ]
                                        )
                                      );
                                      default = null;
                                      description = ''
                                        FromFieldPath specifies how to patch from a field path. The default is
                                        'Optional', which means the patch will be a no-op if the specified
                                        fromFieldPath does not exist. Use 'Required' if the patch should fail if
                                        the specified path does not exist.
                                      '';
                                    };
                                    mergeOptions = mkOption {
                                      type = (
                                        types.nullOr (mkTypedSubmodule {
                                          options = {
                                            appendSlice = mkOption {
                                              type = (types.nullOr types.bool);
                                              default = null;
                                              description = "Specifies that already existing elements in a merged slice should be preserved";
                                            };
                                            keepMapValues = mkOption {
                                              type = (types.nullOr types.bool);
                                              default = null;
                                              description = "Specifies that already existing values in a merged map should be preserved";
                                            };
                                          };
                                        })
                                      );
                                      default = null;
                                      description = "MergeOptions Specifies merge options on a field path.";
                                    };
                                  };
                                })
                              );
                              default = null;
                              description = "Policy configures the specifics of patching behaviour.";
                            };
                            toFieldPath = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = ''
                                ToFieldPath is the path of the field on the resource whose value will
                                be changed with the result of transforms. Leave empty if you'd like to
                                propagate to the same path as fromFieldPath.
                              '';
                            };
                            transforms = mkOption {
                              type = (
                                types.nullOr (
                                  types.listOf (mkTypedSubmodule {
                                    options = {
                                      convert = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              format = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "none"
                                                      "quantity"
                                                      "json"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  The expected input format.

                                                  * `quantity` - parses the input as a K8s [`resource.Quantity`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/resource#Quantity).
                                                  Only used during `string -> float64` conversions.
                                                  * `json` - parses the input as a JSON string.
                                                  Only used during `string -> object` or `string -> list` conversions.

                                                  If this property is null, the default conversion is applied.
                                                '';
                                              };
                                              toType = mkOption {
                                                type = (
                                                  types.enum [
                                                    "string"
                                                    "int"
                                                    "int64"
                                                    "bool"
                                                    "float64"
                                                    "object"
                                                    "array"
                                                  ]
                                                );
                                                description = "ToType is the type of the output of this transform.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "Convert is used to cast the input into the given output type.";
                                      };
                                      map = mkOption {
                                        type = (types.nullOr (types.attrsOf types.anything));
                                        default = null;
                                        description = "Map uses the input as a key in the given map and returns the value.";
                                      };
                                      match = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              fallbackTo = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Value"
                                                      "Input"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Determines to what value the transform should fallback if no pattern matches.";
                                              };
                                              fallbackValue = mkOption {
                                                type = (types.nullOr types.anything);
                                                default = null;
                                                description = ''
                                                  The fallback value that should be returned by the transform if now pattern
                                                  matches.
                                                '';
                                              };
                                              patterns = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.listOf (mkTypedSubmodule {
                                                      options = {
                                                        literal = mkOption {
                                                          type = (types.nullOr types.str);
                                                          default = null;
                                                          description = ''
                                                            Literal exactly matches the input string (case sensitive).
                                                            Is required if `type` is `literal`.
                                                          '';
                                                        };
                                                        regexp = mkOption {
                                                          type = (types.nullOr types.str);
                                                          default = null;
                                                          description = ''
                                                            Regexp to match against the input string.
                                                            Is required if `type` is `regexp`.
                                                          '';
                                                        };
                                                        result = mkOption {
                                                          type = types.anything;
                                                          description = "The value that is used as result of the transform if the pattern matches.";
                                                        };
                                                        type = mkOption {
                                                          type = (
                                                            types.enum [
                                                              "literal"
                                                              "regexp"
                                                            ]
                                                          );
                                                          description = ''
                                                            Type specifies how the pattern matches the input.

                                                            * `literal` - the pattern value has to exactly match (case sensitive) the
                                                            input string. This is the default.

                                                            * `regexp` - the pattern treated as a regular expression against
                                                            which the input string is tested. Crossplane will throw an error if the
                                                            key is not a valid regexp.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  The patterns that should be tested against the input string.
                                                  Patterns are tested in order. The value of the first match is used as
                                                  result of this transform.
                                                '';
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "Match is a more complex version of Map that matches a list of patterns.";
                                      };
                                      math = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              clampMax = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "ClampMax makes sure that the value is not bigger than the given value.";
                                              };
                                              clampMin = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "ClampMin makes sure that the value is not smaller than the given value.";
                                              };
                                              multiply = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "Multiply the value.";
                                              };
                                              type = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Multiply"
                                                      "ClampMin"
                                                      "ClampMax"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Type of the math transform to be run.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          Math is used to transform the input via mathematical operations such as
                                          multiplication.
                                        '';
                                      };
                                      string = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              convert = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "ToUpper"
                                                      "ToLower"
                                                      "ToBase64"
                                                      "FromBase64"
                                                      "ToJson"
                                                      "ToSha1"
                                                      "ToSha256"
                                                      "ToSha512"
                                                      "ToAdler32"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  Optional conversion method to be specified.
                                                  `ToUpper` and `ToLower` change the letter case of the input string.
                                                  `ToBase64` and `FromBase64` perform a base64 conversion based on the input string.
                                                  `ToJson` converts any input value into its raw JSON representation.
                                                  `ToSha1`, `ToSha256` and `ToSha512` generate a hash value based on the input
                                                  converted to JSON.
                                                  `ToAdler32` generate a addler32 hash based on the input string.
                                                '';
                                              };
                                              fmt = mkOption {
                                                type = (types.nullOr types.str);
                                                default = null;
                                                description = ''
                                                  Format the input using a Go format string. See
                                                  https://golang.org/pkg/fmt/ for details.
                                                '';
                                              };
                                              join = mkOption {
                                                type = (
                                                  types.nullOr (mkTypedSubmodule {
                                                    options = {
                                                      separator = mkOption {
                                                        type = types.str;
                                                        description = ''
                                                          Separator defines the character that should separate the values from each
                                                          other in the joined string.
                                                        '';
                                                      };
                                                    };
                                                  })
                                                );
                                                default = null;
                                                description = "Join defines parameters to join a slice of values to a string.";
                                              };
                                              regexp = mkOption {
                                                type = (
                                                  types.nullOr (mkTypedSubmodule {
                                                    options = {
                                                      group = mkOption {
                                                        type = (types.nullOr types.int);
                                                        default = null;
                                                        description = "Group number to match. 0 (the default) matches the entire expression.";
                                                      };
                                                      match = mkOption {
                                                        type = types.str;
                                                        description = ''
                                                          Match string. May optionally include submatches, aka capture groups.
                                                          See https://pkg.go.dev/regexp/ for details.
                                                        '';
                                                      };
                                                    };
                                                  })
                                                );
                                                default = null;
                                                description = "Extract a match from the input using a regular expression.";
                                              };
                                              trim = mkOption {
                                                type = (types.nullOr types.str);
                                                default = null;
                                                description = "Trim the prefix or suffix from the input";
                                              };
                                              type = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Format"
                                                      "Convert"
                                                      "TrimPrefix"
                                                      "TrimSuffix"
                                                      "Regexp"
                                                      "Join"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Type of the string transform to be run.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          String is used to transform the input into a string or a different kind
                                          of string. Note that the input does not necessarily need to be a string.
                                        '';
                                      };
                                      type = mkOption {
                                        type = (
                                          types.enum [
                                            "map"
                                            "match"
                                            "math"
                                            "string"
                                            "convert"
                                          ]
                                        );
                                        description = "Type of the transform to be run.";
                                      };
                                    };
                                  })
                                )
                              );
                              default = null;
                              description = ''
                                Transforms are the list of functions that are used as a FIFO pipe for the
                                input to be transformed.
                              '';
                            };
                            type = mkOption {
                              type = (
                                types.nullOr (
                                  types.enum [
                                    "FromCompositeFieldPath"
                                    "PatchSet"
                                    "ToCompositeFieldPath"
                                    "CombineFromComposite"
                                    "CombineToComposite"
                                  ]
                                )
                              );
                              default = null;
                              description = ''
                                Type sets the patching behaviour to be used. Each patch type may require
                                its own fields to be set on the Patch object.
                              '';
                            };
                          };
                        }))
                        // {
                          emptyValue = { };
                        }
                      );
                      description = "Patches will be applied as an overlay to the base resource.";
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              PatchSets define a named set of patches that may be included by any
              resource in this Composition. PatchSets cannot themselves refer to other
              PatchSets.

              PatchSets are only used by the "Resources" mode of Composition. They
              are ignored by other modes.

              Deprecated: Use Composition Functions instead.
            '';
          };
          pipeline = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    credentials = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              name = mkOption {
                                type = types.str;
                                description = "Name of this set of credentials.";
                              };
                              secretRef = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
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
                                  A SecretRef is a reference to a secret containing credentials that should
                                  be supplied to the function.
                                '';
                              };
                              source = mkOption {
                                type = (
                                  types.enum [
                                    "None"
                                    "Secret"
                                  ]
                                );
                                description = "Source of the function credentials.";
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = "Credentials are optional credentials that the Composition Function needs.";
                    };
                    functionRef = mkOption {
                      type = (
                        mkTypedSubmodule {
                          options = {
                            name = mkOption {
                              type = types.str;
                              description = "Name of the referenced Function.";
                            };
                          };
                        }
                      );
                      description = ''
                        FunctionRef is a reference to the Composition Function this step should
                        execute.
                      '';
                    };
                    input = mkOption {
                      type = (types.nullOr types.attrs);
                      default = null;
                      description = ''
                        Input is an optional, arbitrary Kubernetes resource (i.e. a resource
                        with an apiVersion and kind) that will be passed to the Composition
                        Function as the 'input' of its RunFunctionRequest.
                      '';
                    };
                    step = mkOption {
                      type = types.str;
                      description = "Step name. Must be unique within its Pipeline.";
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              Pipeline is a list of composition function steps that will be used when a
              composite resource referring to this composition is created. One of
              resources and pipeline must be specified - you cannot specify both.

              The Pipeline is only used by the "Pipeline" mode of Composition. It is
              ignored by other modes.
            '';
          };
          publishConnectionDetailsWithStoreConfigRef = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Name of the referenced StoreConfig.";
                  };
                };
              })
            );
            default = null;
            description = ''
              PublishConnectionDetailsWithStoreConfig specifies the secret store config
              with which the connection details of composite resources dynamically
              provisioned using this composition will be published.

              THIS IS AN ALPHA FIELD. Do not use it in production. It is not honored
              unless the relevant Crossplane feature flag is enabled, and may be
              changed or removed without notice.
            '';
          };
          resources = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    base = mkOption {
                      type = types.attrs;
                      description = "Base is the target resource that the patches will be applied on.";
                    };
                    connectionDetails = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              fromConnectionSecretKey = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromConnectionSecretKey is the key that will be used to fetch the value
                                  from the composed resource's connection secret.
                                '';
                              };
                              fromFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromFieldPath is the path of the field on the composed resource whose
                                  value to be used as input. Name must be specified if the type is
                                  FromFieldPath.
                                '';
                              };
                              name = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  Name of the connection secret key that will be propagated to the
                                  connection secret of the composition instance. Leave empty if you'd like
                                  to use the same key name.
                                '';
                              };
                              type = mkOption {
                                type = (
                                  types.nullOr (
                                    types.enum [
                                      "FromConnectionSecretKey"
                                      "FromFieldPath"
                                      "FromValue"
                                    ]
                                  )
                                );
                                default = null;
                                description = ''
                                  Type sets the connection detail fetching behaviour to be used. Each
                                  connection detail type may require its own fields to be set on the
                                  ConnectionDetail object. If the type is omitted Crossplane will attempt
                                  to infer it based on which other fields were specified. If multiple
                                  fields are specified the order of precedence is:
                                  1. FromValue
                                  2. FromConnectionSecretKey
                                  3. FromFieldPath
                                '';
                              };
                              value = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  Value that will be propagated to the connection secret of the composite
                                  resource. May be set to inject a fixed, non-sensitive connection secret
                                  value, for example a well-known port.
                                '';
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = ''
                        ConnectionDetails lists the propagation secret keys from this target
                        resource to the composition instance connection secret.
                      '';
                    };
                    name = mkOption {
                      type = (types.nullOr types.str);
                      default = null;
                      description = ''
                        A Name uniquely identifies this entry within its Composition's resources
                        array. Names are optional but *strongly* recommended. When all entries in
                        the resources array are named entries may added, deleted, and reordered
                        as long as their names do not change. When entries are not named the
                        length and order of the resources array should be treated as immutable.
                        Either all or no entries must be named.
                      '';
                    };
                    patches = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              combine = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      strategy = mkOption {
                                        type = (types.enum [ "string" ]);
                                        description = ''
                                          Strategy defines the strategy to use to combine the input variable values.
                                          Currently only string is supported.
                                        '';
                                      };
                                      string = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              fmt = mkOption {
                                                type = types.str;
                                                description = ''
                                                  Format the input using a Go format string. See
                                                  https://golang.org/pkg/fmt/ for details.
                                                '';
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          String declares that input variables should be combined into a single
                                          string, using the relevant settings for formatting purposes.
                                        '';
                                      };
                                      variables = mkOption {
                                        type = (
                                          (types.listOf (mkTypedSubmodule {
                                            options = {
                                              fromFieldPath = mkOption {
                                                type = types.str;
                                                description = ''
                                                  FromFieldPath is the path of the field on the source whose value is
                                                  to be used as input.
                                                '';
                                              };
                                            };
                                          }))
                                          // {
                                            emptyValue = { };
                                          }
                                        );
                                        description = ''
                                          Variables are the list of variables whose values will be retrieved and
                                          combined.
                                        '';
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = ''
                                  Combine is the patch configuration for a CombineFromComposite or
                                  CombineToComposite patch.
                                '';
                              };
                              fromFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromFieldPath is the path of the field on the resource whose value is
                                  to be used as input. Required when type is FromCompositeFieldPath or
                                  ToCompositeFieldPath.
                                '';
                              };
                              patchSetName = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "PatchSetName to include patches from. Required when type is PatchSet.";
                              };
                              policy = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      fromFieldPath = mkOption {
                                        type = (
                                          types.nullOr (
                                            types.enum [
                                              "Optional"
                                              "Required"
                                            ]
                                          )
                                        );
                                        default = null;
                                        description = ''
                                          FromFieldPath specifies how to patch from a field path. The default is
                                          'Optional', which means the patch will be a no-op if the specified
                                          fromFieldPath does not exist. Use 'Required' if the patch should fail if
                                          the specified path does not exist.
                                        '';
                                      };
                                      mergeOptions = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              appendSlice = mkOption {
                                                type = (types.nullOr types.bool);
                                                default = null;
                                                description = "Specifies that already existing elements in a merged slice should be preserved";
                                              };
                                              keepMapValues = mkOption {
                                                type = (types.nullOr types.bool);
                                                default = null;
                                                description = "Specifies that already existing values in a merged map should be preserved";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "MergeOptions Specifies merge options on a field path.";
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = "Policy configures the specifics of patching behaviour.";
                              };
                              toFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  ToFieldPath is the path of the field on the resource whose value will
                                  be changed with the result of transforms. Leave empty if you'd like to
                                  propagate to the same path as fromFieldPath.
                                '';
                              };
                              transforms = mkOption {
                                type = (
                                  types.nullOr (
                                    types.listOf (mkTypedSubmodule {
                                      options = {
                                        convert = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                format = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "none"
                                                        "quantity"
                                                        "json"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    The expected input format.

                                                    * `quantity` - parses the input as a K8s [`resource.Quantity`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/resource#Quantity).
                                                    Only used during `string -> float64` conversions.
                                                    * `json` - parses the input as a JSON string.
                                                    Only used during `string -> object` or `string -> list` conversions.

                                                    If this property is null, the default conversion is applied.
                                                  '';
                                                };
                                                toType = mkOption {
                                                  type = (
                                                    types.enum [
                                                      "string"
                                                      "int"
                                                      "int64"
                                                      "bool"
                                                      "float64"
                                                      "object"
                                                      "array"
                                                    ]
                                                  );
                                                  description = "ToType is the type of the output of this transform.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = "Convert is used to cast the input into the given output type.";
                                        };
                                        map = mkOption {
                                          type = (types.nullOr (types.attrsOf types.anything));
                                          default = null;
                                          description = "Map uses the input as a key in the given map and returns the value.";
                                        };
                                        match = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                fallbackTo = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Value"
                                                        "Input"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Determines to what value the transform should fallback if no pattern matches.";
                                                };
                                                fallbackValue = mkOption {
                                                  type = (types.nullOr types.anything);
                                                  default = null;
                                                  description = ''
                                                    The fallback value that should be returned by the transform if now pattern
                                                    matches.
                                                  '';
                                                };
                                                patterns = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.listOf (mkTypedSubmodule {
                                                        options = {
                                                          literal = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              Literal exactly matches the input string (case sensitive).
                                                              Is required if `type` is `literal`.
                                                            '';
                                                          };
                                                          regexp = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              Regexp to match against the input string.
                                                              Is required if `type` is `regexp`.
                                                            '';
                                                          };
                                                          result = mkOption {
                                                            type = types.anything;
                                                            description = "The value that is used as result of the transform if the pattern matches.";
                                                          };
                                                          type = mkOption {
                                                            type = (
                                                              types.enum [
                                                                "literal"
                                                                "regexp"
                                                              ]
                                                            );
                                                            description = ''
                                                              Type specifies how the pattern matches the input.

                                                              * `literal` - the pattern value has to exactly match (case sensitive) the
                                                              input string. This is the default.

                                                              * `regexp` - the pattern treated as a regular expression against
                                                              which the input string is tested. Crossplane will throw an error if the
                                                              key is not a valid regexp.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    The patterns that should be tested against the input string.
                                                    Patterns are tested in order. The value of the first match is used as
                                                    result of this transform.
                                                  '';
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = "Match is a more complex version of Map that matches a list of patterns.";
                                        };
                                        math = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                clampMax = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "ClampMax makes sure that the value is not bigger than the given value.";
                                                };
                                                clampMin = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "ClampMin makes sure that the value is not smaller than the given value.";
                                                };
                                                multiply = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "Multiply the value.";
                                                };
                                                type = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Multiply"
                                                        "ClampMin"
                                                        "ClampMax"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Type of the math transform to be run.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = ''
                                            Math is used to transform the input via mathematical operations such as
                                            multiplication.
                                          '';
                                        };
                                        string = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                convert = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "ToUpper"
                                                        "ToLower"
                                                        "ToBase64"
                                                        "FromBase64"
                                                        "ToJson"
                                                        "ToSha1"
                                                        "ToSha256"
                                                        "ToSha512"
                                                        "ToAdler32"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    Optional conversion method to be specified.
                                                    `ToUpper` and `ToLower` change the letter case of the input string.
                                                    `ToBase64` and `FromBase64` perform a base64 conversion based on the input string.
                                                    `ToJson` converts any input value into its raw JSON representation.
                                                    `ToSha1`, `ToSha256` and `ToSha512` generate a hash value based on the input
                                                    converted to JSON.
                                                    `ToAdler32` generate a addler32 hash based on the input string.
                                                  '';
                                                };
                                                fmt = mkOption {
                                                  type = (types.nullOr types.str);
                                                  default = null;
                                                  description = ''
                                                    Format the input using a Go format string. See
                                                    https://golang.org/pkg/fmt/ for details.
                                                  '';
                                                };
                                                join = mkOption {
                                                  type = (
                                                    types.nullOr (mkTypedSubmodule {
                                                      options = {
                                                        separator = mkOption {
                                                          type = types.str;
                                                          description = ''
                                                            Separator defines the character that should separate the values from each
                                                            other in the joined string.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  );
                                                  default = null;
                                                  description = "Join defines parameters to join a slice of values to a string.";
                                                };
                                                regexp = mkOption {
                                                  type = (
                                                    types.nullOr (mkTypedSubmodule {
                                                      options = {
                                                        group = mkOption {
                                                          type = (types.nullOr types.int);
                                                          default = null;
                                                          description = "Group number to match. 0 (the default) matches the entire expression.";
                                                        };
                                                        match = mkOption {
                                                          type = types.str;
                                                          description = ''
                                                            Match string. May optionally include submatches, aka capture groups.
                                                            See https://pkg.go.dev/regexp/ for details.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  );
                                                  default = null;
                                                  description = "Extract a match from the input using a regular expression.";
                                                };
                                                trim = mkOption {
                                                  type = (types.nullOr types.str);
                                                  default = null;
                                                  description = "Trim the prefix or suffix from the input";
                                                };
                                                type = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Format"
                                                        "Convert"
                                                        "TrimPrefix"
                                                        "TrimSuffix"
                                                        "Regexp"
                                                        "Join"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Type of the string transform to be run.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = ''
                                            String is used to transform the input into a string or a different kind
                                            of string. Note that the input does not necessarily need to be a string.
                                          '';
                                        };
                                        type = mkOption {
                                          type = (
                                            types.enum [
                                              "map"
                                              "match"
                                              "math"
                                              "string"
                                              "convert"
                                            ]
                                          );
                                          description = "Type of the transform to be run.";
                                        };
                                      };
                                    })
                                  )
                                );
                                default = null;
                                description = ''
                                  Transforms are the list of functions that are used as a FIFO pipe for the
                                  input to be transformed.
                                '';
                              };
                              type = mkOption {
                                type = (
                                  types.nullOr (
                                    types.enum [
                                      "FromCompositeFieldPath"
                                      "PatchSet"
                                      "ToCompositeFieldPath"
                                      "CombineFromComposite"
                                      "CombineToComposite"
                                    ]
                                  )
                                );
                                default = null;
                                description = ''
                                  Type sets the patching behaviour to be used. Each patch type may require
                                  its own fields to be set on the Patch object.
                                '';
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = "Patches will be applied as overlay to the base resource.";
                    };
                    readinessChecks = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              fieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "FieldPath shows the path of the field whose value will be used.";
                              };
                              matchCondition = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      status = mkOption {
                                        type = types.str;
                                        description = "Status is the status of the condition you'd like to match.";
                                      };
                                      type = mkOption {
                                        type = types.str;
                                        description = "Type indicates the type of condition you'd like to use.";
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = "MatchCondition specifies the condition you'd like to match if you're using \"MatchCondition\" type.";
                              };
                              matchInteger = mkOption {
                                type = (types.nullOr types.int);
                                default = null;
                                description = "MatchInt is the value you'd like to match if you're using \"MatchInt\" type.";
                              };
                              matchString = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "MatchString is the value you'd like to match if you're using \"MatchString\" type.";
                              };
                              type = mkOption {
                                type = (
                                  types.enum [
                                    "MatchString"
                                    "MatchInteger"
                                    "NonEmpty"
                                    "MatchCondition"
                                    "MatchTrue"
                                    "MatchFalse"
                                    "None"
                                  ]
                                );
                                description = "Type indicates the type of probe you'd like to use.";
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = ''
                        ReadinessChecks allows users to define custom readiness checks. All checks
                        have to return true in order for resource to be considered ready. The
                        default readiness check is to have the "Ready" condition to be "True".
                      '';
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              Resources is a list of resource templates that will be used when a
              composite resource referring to this composition is created.

              Resources are only used by the "Resources" mode of Composition. They are
              ignored by other modes.

              Deprecated: Use Composition Functions instead.
            '';
          };
          revision = mkOption {
            type = types.int;
            description = ''
              Revision number. Newer revisions have larger numbers.

              This number can change. When a Composition transitions from state A
              -> B -> A there will be only two CompositionRevisions. Crossplane will
              edit the original CompositionRevision to change its revision number from
              0 to 2.
            '';
          };
          writeConnectionSecretsToNamespace = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              WriteConnectionSecretsToNamespace specifies the namespace in which the
              connection secrets of composite resource dynamically provisioned using
              this composition will be created.
              This field is planned to be replaced in a future release in favor of
              PublishConnectionDetailsWithStoreConfigRef. Currently, both could be
              set independently and connection details would be published to both
              without affecting each other as long as related fields at MR level
              specified.
            '';
          };
        };
      }
    );
  };

  Composition = mkResource {
    apiVersion = "apiextensions.crossplane.io/v1";
    kind = "Composition";
    specType = (
      mkTypedSubmodule {
        options = {
          compositeTypeRef = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  apiVersion = mkOption {
                    type = types.str;
                    description = "APIVersion of the type.";
                  };
                  kind = mkOption {
                    type = types.str;
                    description = "Kind of the type.";
                  };
                };
              }
            );
            description = ''
              CompositeTypeRef specifies the type of composite resource that this
              composition is compatible with.
            '';
          };
          mode = mkOption {
            type = (
              types.nullOr (
                types.enum [
                  "Resources"
                  "Pipeline"
                ]
              )
            );
            default = null;
            description = ''
              Mode controls what type or "mode" of Composition will be used.

              "Pipeline" indicates that a Composition specifies a pipeline of
              Composition Functions, each of which is responsible for producing
              composed resources that Crossplane should create or update.

              "Resources" indicates that a Composition uses what is commonly referred
              to as "Patch & Transform" or P&T composition. This mode of Composition
              uses an array of resources, each a template for a composed resource.

              All Compositions should use Pipeline mode. Resources mode is deprecated.
              Resources mode won't be removed in Crossplane 1.x, and will remain the
              default to avoid breaking legacy Compositions. However, it's no longer
              accepting new features, and only accepting security related bug fixes.
            '';
          };
          patchSets = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    name = mkOption {
                      type = types.str;
                      description = "Name of this PatchSet.";
                    };
                    patches = mkOption {
                      type = (
                        (types.listOf (mkTypedSubmodule {
                          options = {
                            combine = mkOption {
                              type = (
                                types.nullOr (mkTypedSubmodule {
                                  options = {
                                    strategy = mkOption {
                                      type = (types.enum [ "string" ]);
                                      description = ''
                                        Strategy defines the strategy to use to combine the input variable values.
                                        Currently only string is supported.
                                      '';
                                    };
                                    string = mkOption {
                                      type = (
                                        types.nullOr (mkTypedSubmodule {
                                          options = {
                                            fmt = mkOption {
                                              type = types.str;
                                              description = ''
                                                Format the input using a Go format string. See
                                                https://golang.org/pkg/fmt/ for details.
                                              '';
                                            };
                                          };
                                        })
                                      );
                                      default = null;
                                      description = ''
                                        String declares that input variables should be combined into a single
                                        string, using the relevant settings for formatting purposes.
                                      '';
                                    };
                                    variables = mkOption {
                                      type = (
                                        (types.listOf (mkTypedSubmodule {
                                          options = {
                                            fromFieldPath = mkOption {
                                              type = types.str;
                                              description = ''
                                                FromFieldPath is the path of the field on the source whose value is
                                                to be used as input.
                                              '';
                                            };
                                          };
                                        }))
                                        // {
                                          emptyValue = { };
                                        }
                                      );
                                      description = ''
                                        Variables are the list of variables whose values will be retrieved and
                                        combined.
                                      '';
                                    };
                                  };
                                })
                              );
                              default = null;
                              description = ''
                                Combine is the patch configuration for a CombineFromComposite or
                                CombineToComposite patch.
                              '';
                            };
                            fromFieldPath = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = ''
                                FromFieldPath is the path of the field on the resource whose value is
                                to be used as input. Required when type is FromCompositeFieldPath or
                                ToCompositeFieldPath.
                              '';
                            };
                            patchSetName = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = "PatchSetName to include patches from. Required when type is PatchSet.";
                            };
                            policy = mkOption {
                              type = (
                                types.nullOr (mkTypedSubmodule {
                                  options = {
                                    fromFieldPath = mkOption {
                                      type = (
                                        types.nullOr (
                                          types.enum [
                                            "Optional"
                                            "Required"
                                          ]
                                        )
                                      );
                                      default = null;
                                      description = ''
                                        FromFieldPath specifies how to patch from a field path. The default is
                                        'Optional', which means the patch will be a no-op if the specified
                                        fromFieldPath does not exist. Use 'Required' if the patch should fail if
                                        the specified path does not exist.
                                      '';
                                    };
                                    mergeOptions = mkOption {
                                      type = (
                                        types.nullOr (mkTypedSubmodule {
                                          options = {
                                            appendSlice = mkOption {
                                              type = (types.nullOr types.bool);
                                              default = null;
                                              description = "Specifies that already existing elements in a merged slice should be preserved";
                                            };
                                            keepMapValues = mkOption {
                                              type = (types.nullOr types.bool);
                                              default = null;
                                              description = "Specifies that already existing values in a merged map should be preserved";
                                            };
                                          };
                                        })
                                      );
                                      default = null;
                                      description = "MergeOptions Specifies merge options on a field path.";
                                    };
                                  };
                                })
                              );
                              default = null;
                              description = "Policy configures the specifics of patching behaviour.";
                            };
                            toFieldPath = mkOption {
                              type = (types.nullOr types.str);
                              default = null;
                              description = ''
                                ToFieldPath is the path of the field on the resource whose value will
                                be changed with the result of transforms. Leave empty if you'd like to
                                propagate to the same path as fromFieldPath.
                              '';
                            };
                            transforms = mkOption {
                              type = (
                                types.nullOr (
                                  types.listOf (mkTypedSubmodule {
                                    options = {
                                      convert = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              format = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "none"
                                                      "quantity"
                                                      "json"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  The expected input format.

                                                  * `quantity` - parses the input as a K8s [`resource.Quantity`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/resource#Quantity).
                                                  Only used during `string -> float64` conversions.
                                                  * `json` - parses the input as a JSON string.
                                                  Only used during `string -> object` or `string -> list` conversions.

                                                  If this property is null, the default conversion is applied.
                                                '';
                                              };
                                              toType = mkOption {
                                                type = (
                                                  types.enum [
                                                    "string"
                                                    "int"
                                                    "int64"
                                                    "bool"
                                                    "float64"
                                                    "object"
                                                    "array"
                                                  ]
                                                );
                                                description = "ToType is the type of the output of this transform.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "Convert is used to cast the input into the given output type.";
                                      };
                                      map = mkOption {
                                        type = (types.nullOr (types.attrsOf types.anything));
                                        default = null;
                                        description = "Map uses the input as a key in the given map and returns the value.";
                                      };
                                      match = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              fallbackTo = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Value"
                                                      "Input"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Determines to what value the transform should fallback if no pattern matches.";
                                              };
                                              fallbackValue = mkOption {
                                                type = (types.nullOr types.anything);
                                                default = null;
                                                description = ''
                                                  The fallback value that should be returned by the transform if now pattern
                                                  matches.
                                                '';
                                              };
                                              patterns = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.listOf (mkTypedSubmodule {
                                                      options = {
                                                        literal = mkOption {
                                                          type = (types.nullOr types.str);
                                                          default = null;
                                                          description = ''
                                                            Literal exactly matches the input string (case sensitive).
                                                            Is required if `type` is `literal`.
                                                          '';
                                                        };
                                                        regexp = mkOption {
                                                          type = (types.nullOr types.str);
                                                          default = null;
                                                          description = ''
                                                            Regexp to match against the input string.
                                                            Is required if `type` is `regexp`.
                                                          '';
                                                        };
                                                        result = mkOption {
                                                          type = types.anything;
                                                          description = "The value that is used as result of the transform if the pattern matches.";
                                                        };
                                                        type = mkOption {
                                                          type = (
                                                            types.enum [
                                                              "literal"
                                                              "regexp"
                                                            ]
                                                          );
                                                          description = ''
                                                            Type specifies how the pattern matches the input.

                                                            * `literal` - the pattern value has to exactly match (case sensitive) the
                                                            input string. This is the default.

                                                            * `regexp` - the pattern treated as a regular expression against
                                                            which the input string is tested. Crossplane will throw an error if the
                                                            key is not a valid regexp.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  The patterns that should be tested against the input string.
                                                  Patterns are tested in order. The value of the first match is used as
                                                  result of this transform.
                                                '';
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "Match is a more complex version of Map that matches a list of patterns.";
                                      };
                                      math = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              clampMax = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "ClampMax makes sure that the value is not bigger than the given value.";
                                              };
                                              clampMin = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "ClampMin makes sure that the value is not smaller than the given value.";
                                              };
                                              multiply = mkOption {
                                                type = (types.nullOr types.int);
                                                default = null;
                                                description = "Multiply the value.";
                                              };
                                              type = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Multiply"
                                                      "ClampMin"
                                                      "ClampMax"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Type of the math transform to be run.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          Math is used to transform the input via mathematical operations such as
                                          multiplication.
                                        '';
                                      };
                                      string = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              convert = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "ToUpper"
                                                      "ToLower"
                                                      "ToBase64"
                                                      "FromBase64"
                                                      "ToJson"
                                                      "ToSha1"
                                                      "ToSha256"
                                                      "ToSha512"
                                                      "ToAdler32"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = ''
                                                  Optional conversion method to be specified.
                                                  `ToUpper` and `ToLower` change the letter case of the input string.
                                                  `ToBase64` and `FromBase64` perform a base64 conversion based on the input string.
                                                  `ToJson` converts any input value into its raw JSON representation.
                                                  `ToSha1`, `ToSha256` and `ToSha512` generate a hash value based on the input
                                                  converted to JSON.
                                                  `ToAdler32` generate a addler32 hash based on the input string.
                                                '';
                                              };
                                              fmt = mkOption {
                                                type = (types.nullOr types.str);
                                                default = null;
                                                description = ''
                                                  Format the input using a Go format string. See
                                                  https://golang.org/pkg/fmt/ for details.
                                                '';
                                              };
                                              join = mkOption {
                                                type = (
                                                  types.nullOr (mkTypedSubmodule {
                                                    options = {
                                                      separator = mkOption {
                                                        type = types.str;
                                                        description = ''
                                                          Separator defines the character that should separate the values from each
                                                          other in the joined string.
                                                        '';
                                                      };
                                                    };
                                                  })
                                                );
                                                default = null;
                                                description = "Join defines parameters to join a slice of values to a string.";
                                              };
                                              regexp = mkOption {
                                                type = (
                                                  types.nullOr (mkTypedSubmodule {
                                                    options = {
                                                      group = mkOption {
                                                        type = (types.nullOr types.int);
                                                        default = null;
                                                        description = "Group number to match. 0 (the default) matches the entire expression.";
                                                      };
                                                      match = mkOption {
                                                        type = types.str;
                                                        description = ''
                                                          Match string. May optionally include submatches, aka capture groups.
                                                          See https://pkg.go.dev/regexp/ for details.
                                                        '';
                                                      };
                                                    };
                                                  })
                                                );
                                                default = null;
                                                description = "Extract a match from the input using a regular expression.";
                                              };
                                              trim = mkOption {
                                                type = (types.nullOr types.str);
                                                default = null;
                                                description = "Trim the prefix or suffix from the input";
                                              };
                                              type = mkOption {
                                                type = (
                                                  types.nullOr (
                                                    types.enum [
                                                      "Format"
                                                      "Convert"
                                                      "TrimPrefix"
                                                      "TrimSuffix"
                                                      "Regexp"
                                                      "Join"
                                                    ]
                                                  )
                                                );
                                                default = null;
                                                description = "Type of the string transform to be run.";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          String is used to transform the input into a string or a different kind
                                          of string. Note that the input does not necessarily need to be a string.
                                        '';
                                      };
                                      type = mkOption {
                                        type = (
                                          types.enum [
                                            "map"
                                            "match"
                                            "math"
                                            "string"
                                            "convert"
                                          ]
                                        );
                                        description = "Type of the transform to be run.";
                                      };
                                    };
                                  })
                                )
                              );
                              default = null;
                              description = ''
                                Transforms are the list of functions that are used as a FIFO pipe for the
                                input to be transformed.
                              '';
                            };
                            type = mkOption {
                              type = (
                                types.nullOr (
                                  types.enum [
                                    "FromCompositeFieldPath"
                                    "PatchSet"
                                    "ToCompositeFieldPath"
                                    "CombineFromComposite"
                                    "CombineToComposite"
                                  ]
                                )
                              );
                              default = null;
                              description = ''
                                Type sets the patching behaviour to be used. Each patch type may require
                                its own fields to be set on the Patch object.
                              '';
                            };
                          };
                        }))
                        // {
                          emptyValue = { };
                        }
                      );
                      description = "Patches will be applied as an overlay to the base resource.";
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              PatchSets define a named set of patches that may be included by any
              resource in this Composition. PatchSets cannot themselves refer to other
              PatchSets.

              PatchSets are only used by the "Resources" mode of Composition. They
              are ignored by other modes.

              Deprecated: Use Composition Functions instead.
            '';
          };
          pipeline = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    credentials = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              name = mkOption {
                                type = types.str;
                                description = "Name of this set of credentials.";
                              };
                              secretRef = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
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
                                  A SecretRef is a reference to a secret containing credentials that should
                                  be supplied to the function.
                                '';
                              };
                              source = mkOption {
                                type = (
                                  types.enum [
                                    "None"
                                    "Secret"
                                  ]
                                );
                                description = "Source of the function credentials.";
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = "Credentials are optional credentials that the Composition Function needs.";
                    };
                    functionRef = mkOption {
                      type = (
                        mkTypedSubmodule {
                          options = {
                            name = mkOption {
                              type = types.str;
                              description = "Name of the referenced Function.";
                            };
                          };
                        }
                      );
                      description = ''
                        FunctionRef is a reference to the Composition Function this step should
                        execute.
                      '';
                    };
                    input = mkOption {
                      type = (types.nullOr types.attrs);
                      default = null;
                      description = ''
                        Input is an optional, arbitrary Kubernetes resource (i.e. a resource
                        with an apiVersion and kind) that will be passed to the Composition
                        Function as the 'input' of its RunFunctionRequest.
                      '';
                    };
                    step = mkOption {
                      type = types.str;
                      description = "Step name. Must be unique within its Pipeline.";
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              Pipeline is a list of composition function steps that will be used when a
              composite resource referring to this composition is created. One of
              resources and pipeline must be specified - you cannot specify both.

              The Pipeline is only used by the "Pipeline" mode of Composition. It is
              ignored by other modes.
            '';
          };
          publishConnectionDetailsWithStoreConfigRef = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  name = mkOption {
                    type = types.str;
                    description = "Name of the referenced StoreConfig.";
                  };
                };
              })
            );
            default = null;
            description = ''
              PublishConnectionDetailsWithStoreConfig specifies the secret store config
              with which the connection details of composite resources dynamically
              provisioned using this composition will be published.

              THIS IS AN ALPHA FIELD. Do not use it in production. It is not honored
              unless the relevant Crossplane feature flag is enabled, and may be
              changed or removed without notice.
            '';
          };
          resources = mkOption {
            type = (
              types.nullOr (
                types.listOf (mkTypedSubmodule {
                  options = {
                    base = mkOption {
                      type = types.attrs;
                      description = "Base is the target resource that the patches will be applied on.";
                    };
                    connectionDetails = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              fromConnectionSecretKey = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromConnectionSecretKey is the key that will be used to fetch the value
                                  from the composed resource's connection secret.
                                '';
                              };
                              fromFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromFieldPath is the path of the field on the composed resource whose
                                  value to be used as input. Name must be specified if the type is
                                  FromFieldPath.
                                '';
                              };
                              name = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  Name of the connection secret key that will be propagated to the
                                  connection secret of the composition instance. Leave empty if you'd like
                                  to use the same key name.
                                '';
                              };
                              type = mkOption {
                                type = (
                                  types.nullOr (
                                    types.enum [
                                      "FromConnectionSecretKey"
                                      "FromFieldPath"
                                      "FromValue"
                                    ]
                                  )
                                );
                                default = null;
                                description = ''
                                  Type sets the connection detail fetching behaviour to be used. Each
                                  connection detail type may require its own fields to be set on the
                                  ConnectionDetail object. If the type is omitted Crossplane will attempt
                                  to infer it based on which other fields were specified. If multiple
                                  fields are specified the order of precedence is:
                                  1. FromValue
                                  2. FromConnectionSecretKey
                                  3. FromFieldPath
                                '';
                              };
                              value = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  Value that will be propagated to the connection secret of the composite
                                  resource. May be set to inject a fixed, non-sensitive connection secret
                                  value, for example a well-known port.
                                '';
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = ''
                        ConnectionDetails lists the propagation secret keys from this target
                        resource to the composition instance connection secret.
                      '';
                    };
                    name = mkOption {
                      type = (types.nullOr types.str);
                      default = null;
                      description = ''
                        A Name uniquely identifies this entry within its Composition's resources
                        array. Names are optional but *strongly* recommended. When all entries in
                        the resources array are named entries may added, deleted, and reordered
                        as long as their names do not change. When entries are not named the
                        length and order of the resources array should be treated as immutable.
                        Either all or no entries must be named.
                      '';
                    };
                    patches = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              combine = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      strategy = mkOption {
                                        type = (types.enum [ "string" ]);
                                        description = ''
                                          Strategy defines the strategy to use to combine the input variable values.
                                          Currently only string is supported.
                                        '';
                                      };
                                      string = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              fmt = mkOption {
                                                type = types.str;
                                                description = ''
                                                  Format the input using a Go format string. See
                                                  https://golang.org/pkg/fmt/ for details.
                                                '';
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = ''
                                          String declares that input variables should be combined into a single
                                          string, using the relevant settings for formatting purposes.
                                        '';
                                      };
                                      variables = mkOption {
                                        type = (
                                          (types.listOf (mkTypedSubmodule {
                                            options = {
                                              fromFieldPath = mkOption {
                                                type = types.str;
                                                description = ''
                                                  FromFieldPath is the path of the field on the source whose value is
                                                  to be used as input.
                                                '';
                                              };
                                            };
                                          }))
                                          // {
                                            emptyValue = { };
                                          }
                                        );
                                        description = ''
                                          Variables are the list of variables whose values will be retrieved and
                                          combined.
                                        '';
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = ''
                                  Combine is the patch configuration for a CombineFromComposite or
                                  CombineToComposite patch.
                                '';
                              };
                              fromFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  FromFieldPath is the path of the field on the resource whose value is
                                  to be used as input. Required when type is FromCompositeFieldPath or
                                  ToCompositeFieldPath.
                                '';
                              };
                              patchSetName = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "PatchSetName to include patches from. Required when type is PatchSet.";
                              };
                              policy = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      fromFieldPath = mkOption {
                                        type = (
                                          types.nullOr (
                                            types.enum [
                                              "Optional"
                                              "Required"
                                            ]
                                          )
                                        );
                                        default = null;
                                        description = ''
                                          FromFieldPath specifies how to patch from a field path. The default is
                                          'Optional', which means the patch will be a no-op if the specified
                                          fromFieldPath does not exist. Use 'Required' if the patch should fail if
                                          the specified path does not exist.
                                        '';
                                      };
                                      mergeOptions = mkOption {
                                        type = (
                                          types.nullOr (mkTypedSubmodule {
                                            options = {
                                              appendSlice = mkOption {
                                                type = (types.nullOr types.bool);
                                                default = null;
                                                description = "Specifies that already existing elements in a merged slice should be preserved";
                                              };
                                              keepMapValues = mkOption {
                                                type = (types.nullOr types.bool);
                                                default = null;
                                                description = "Specifies that already existing values in a merged map should be preserved";
                                              };
                                            };
                                          })
                                        );
                                        default = null;
                                        description = "MergeOptions Specifies merge options on a field path.";
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = "Policy configures the specifics of patching behaviour.";
                              };
                              toFieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = ''
                                  ToFieldPath is the path of the field on the resource whose value will
                                  be changed with the result of transforms. Leave empty if you'd like to
                                  propagate to the same path as fromFieldPath.
                                '';
                              };
                              transforms = mkOption {
                                type = (
                                  types.nullOr (
                                    types.listOf (mkTypedSubmodule {
                                      options = {
                                        convert = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                format = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "none"
                                                        "quantity"
                                                        "json"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    The expected input format.

                                                    * `quantity` - parses the input as a K8s [`resource.Quantity`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/resource#Quantity).
                                                    Only used during `string -> float64` conversions.
                                                    * `json` - parses the input as a JSON string.
                                                    Only used during `string -> object` or `string -> list` conversions.

                                                    If this property is null, the default conversion is applied.
                                                  '';
                                                };
                                                toType = mkOption {
                                                  type = (
                                                    types.enum [
                                                      "string"
                                                      "int"
                                                      "int64"
                                                      "bool"
                                                      "float64"
                                                      "object"
                                                      "array"
                                                    ]
                                                  );
                                                  description = "ToType is the type of the output of this transform.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = "Convert is used to cast the input into the given output type.";
                                        };
                                        map = mkOption {
                                          type = (types.nullOr (types.attrsOf types.anything));
                                          default = null;
                                          description = "Map uses the input as a key in the given map and returns the value.";
                                        };
                                        match = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                fallbackTo = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Value"
                                                        "Input"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Determines to what value the transform should fallback if no pattern matches.";
                                                };
                                                fallbackValue = mkOption {
                                                  type = (types.nullOr types.anything);
                                                  default = null;
                                                  description = ''
                                                    The fallback value that should be returned by the transform if now pattern
                                                    matches.
                                                  '';
                                                };
                                                patterns = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.listOf (mkTypedSubmodule {
                                                        options = {
                                                          literal = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              Literal exactly matches the input string (case sensitive).
                                                              Is required if `type` is `literal`.
                                                            '';
                                                          };
                                                          regexp = mkOption {
                                                            type = (types.nullOr types.str);
                                                            default = null;
                                                            description = ''
                                                              Regexp to match against the input string.
                                                              Is required if `type` is `regexp`.
                                                            '';
                                                          };
                                                          result = mkOption {
                                                            type = types.anything;
                                                            description = "The value that is used as result of the transform if the pattern matches.";
                                                          };
                                                          type = mkOption {
                                                            type = (
                                                              types.enum [
                                                                "literal"
                                                                "regexp"
                                                              ]
                                                            );
                                                            description = ''
                                                              Type specifies how the pattern matches the input.

                                                              * `literal` - the pattern value has to exactly match (case sensitive) the
                                                              input string. This is the default.

                                                              * `regexp` - the pattern treated as a regular expression against
                                                              which the input string is tested. Crossplane will throw an error if the
                                                              key is not a valid regexp.
                                                            '';
                                                          };
                                                        };
                                                      })
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    The patterns that should be tested against the input string.
                                                    Patterns are tested in order. The value of the first match is used as
                                                    result of this transform.
                                                  '';
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = "Match is a more complex version of Map that matches a list of patterns.";
                                        };
                                        math = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                clampMax = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "ClampMax makes sure that the value is not bigger than the given value.";
                                                };
                                                clampMin = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "ClampMin makes sure that the value is not smaller than the given value.";
                                                };
                                                multiply = mkOption {
                                                  type = (types.nullOr types.int);
                                                  default = null;
                                                  description = "Multiply the value.";
                                                };
                                                type = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Multiply"
                                                        "ClampMin"
                                                        "ClampMax"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Type of the math transform to be run.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = ''
                                            Math is used to transform the input via mathematical operations such as
                                            multiplication.
                                          '';
                                        };
                                        string = mkOption {
                                          type = (
                                            types.nullOr (mkTypedSubmodule {
                                              options = {
                                                convert = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "ToUpper"
                                                        "ToLower"
                                                        "ToBase64"
                                                        "FromBase64"
                                                        "ToJson"
                                                        "ToSha1"
                                                        "ToSha256"
                                                        "ToSha512"
                                                        "ToAdler32"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = ''
                                                    Optional conversion method to be specified.
                                                    `ToUpper` and `ToLower` change the letter case of the input string.
                                                    `ToBase64` and `FromBase64` perform a base64 conversion based on the input string.
                                                    `ToJson` converts any input value into its raw JSON representation.
                                                    `ToSha1`, `ToSha256` and `ToSha512` generate a hash value based on the input
                                                    converted to JSON.
                                                    `ToAdler32` generate a addler32 hash based on the input string.
                                                  '';
                                                };
                                                fmt = mkOption {
                                                  type = (types.nullOr types.str);
                                                  default = null;
                                                  description = ''
                                                    Format the input using a Go format string. See
                                                    https://golang.org/pkg/fmt/ for details.
                                                  '';
                                                };
                                                join = mkOption {
                                                  type = (
                                                    types.nullOr (mkTypedSubmodule {
                                                      options = {
                                                        separator = mkOption {
                                                          type = types.str;
                                                          description = ''
                                                            Separator defines the character that should separate the values from each
                                                            other in the joined string.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  );
                                                  default = null;
                                                  description = "Join defines parameters to join a slice of values to a string.";
                                                };
                                                regexp = mkOption {
                                                  type = (
                                                    types.nullOr (mkTypedSubmodule {
                                                      options = {
                                                        group = mkOption {
                                                          type = (types.nullOr types.int);
                                                          default = null;
                                                          description = "Group number to match. 0 (the default) matches the entire expression.";
                                                        };
                                                        match = mkOption {
                                                          type = types.str;
                                                          description = ''
                                                            Match string. May optionally include submatches, aka capture groups.
                                                            See https://pkg.go.dev/regexp/ for details.
                                                          '';
                                                        };
                                                      };
                                                    })
                                                  );
                                                  default = null;
                                                  description = "Extract a match from the input using a regular expression.";
                                                };
                                                trim = mkOption {
                                                  type = (types.nullOr types.str);
                                                  default = null;
                                                  description = "Trim the prefix or suffix from the input";
                                                };
                                                type = mkOption {
                                                  type = (
                                                    types.nullOr (
                                                      types.enum [
                                                        "Format"
                                                        "Convert"
                                                        "TrimPrefix"
                                                        "TrimSuffix"
                                                        "Regexp"
                                                        "Join"
                                                      ]
                                                    )
                                                  );
                                                  default = null;
                                                  description = "Type of the string transform to be run.";
                                                };
                                              };
                                            })
                                          );
                                          default = null;
                                          description = ''
                                            String is used to transform the input into a string or a different kind
                                            of string. Note that the input does not necessarily need to be a string.
                                          '';
                                        };
                                        type = mkOption {
                                          type = (
                                            types.enum [
                                              "map"
                                              "match"
                                              "math"
                                              "string"
                                              "convert"
                                            ]
                                          );
                                          description = "Type of the transform to be run.";
                                        };
                                      };
                                    })
                                  )
                                );
                                default = null;
                                description = ''
                                  Transforms are the list of functions that are used as a FIFO pipe for the
                                  input to be transformed.
                                '';
                              };
                              type = mkOption {
                                type = (
                                  types.nullOr (
                                    types.enum [
                                      "FromCompositeFieldPath"
                                      "PatchSet"
                                      "ToCompositeFieldPath"
                                      "CombineFromComposite"
                                      "CombineToComposite"
                                    ]
                                  )
                                );
                                default = null;
                                description = ''
                                  Type sets the patching behaviour to be used. Each patch type may require
                                  its own fields to be set on the Patch object.
                                '';
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = "Patches will be applied as overlay to the base resource.";
                    };
                    readinessChecks = mkOption {
                      type = (
                        types.nullOr (
                          types.listOf (mkTypedSubmodule {
                            options = {
                              fieldPath = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "FieldPath shows the path of the field whose value will be used.";
                              };
                              matchCondition = mkOption {
                                type = (
                                  types.nullOr (mkTypedSubmodule {
                                    options = {
                                      status = mkOption {
                                        type = types.str;
                                        description = "Status is the status of the condition you'd like to match.";
                                      };
                                      type = mkOption {
                                        type = types.str;
                                        description = "Type indicates the type of condition you'd like to use.";
                                      };
                                    };
                                  })
                                );
                                default = null;
                                description = "MatchCondition specifies the condition you'd like to match if you're using \"MatchCondition\" type.";
                              };
                              matchInteger = mkOption {
                                type = (types.nullOr types.int);
                                default = null;
                                description = "MatchInt is the value you'd like to match if you're using \"MatchInt\" type.";
                              };
                              matchString = mkOption {
                                type = (types.nullOr types.str);
                                default = null;
                                description = "MatchString is the value you'd like to match if you're using \"MatchString\" type.";
                              };
                              type = mkOption {
                                type = (
                                  types.enum [
                                    "MatchString"
                                    "MatchInteger"
                                    "NonEmpty"
                                    "MatchCondition"
                                    "MatchTrue"
                                    "MatchFalse"
                                    "None"
                                  ]
                                );
                                description = "Type indicates the type of probe you'd like to use.";
                              };
                            };
                          })
                        )
                      );
                      default = null;
                      description = ''
                        ReadinessChecks allows users to define custom readiness checks. All checks
                        have to return true in order for resource to be considered ready. The
                        default readiness check is to have the "Ready" condition to be "True".
                      '';
                    };
                  };
                })
              )
            );
            default = null;
            description = ''
              Resources is a list of resource templates that will be used when a
              composite resource referring to this composition is created.

              Resources are only used by the "Resources" mode of Composition. They are
              ignored by other modes.

              Deprecated: Use Composition Functions instead.
            '';
          };
          writeConnectionSecretsToNamespace = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = ''
              WriteConnectionSecretsToNamespace specifies the namespace in which the
              connection secrets of composite resource dynamically provisioned using
              this composition will be created.
              This field is planned to be replaced in a future release in favor of
              PublishConnectionDetailsWithStoreConfigRef. Currently, both could be
              set independently and connection details would be published to both
              without affecting each other as long as related fields at MR level
              specified.
            '';
          };
        };
      }
    );
  };

  EnvironmentConfig = mkResource {
    apiVersion = "apiextensions.crossplane.io/v1alpha1";
    kind = "EnvironmentConfig";
    specType = types.attrs;
    topLevel = {
      data = mkOption {
        type = (types.nullOr (types.attrsOf types.anything));
        default = null;
        description = ''
          The data of this EnvironmentConfig.
          This may contain any kind of structure that can be serialized into JSON.
        '';
      };
    };
  };

  Usage = mkResource {
    apiVersion = "apiextensions.crossplane.io/v1alpha1";
    kind = "Usage";
    specType = (
      mkTypedSubmodule {
        options = {
          by = mkOption {
            type = (
              types.nullOr (mkTypedSubmodule {
                options = {
                  apiVersion = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "API version of the referent.";
                  };
                  kind = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      Kind of the referent.
                      More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
                    '';
                  };
                  resourceRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          name = mkOption {
                            type = types.str;
                            description = "Name of the referent.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "Reference to the resource.";
                  };
                  resourceSelector = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          matchControllerRef = mkOption {
                            type = (types.nullOr types.bool);
                            default = null;
                            description = ''
                              MatchControllerRef ensures an object with the same controller reference
                              as the selecting object is selected.
                            '';
                          };
                          matchLabels = mkOption {
                            type = (types.nullOr (types.attrsOf types.str));
                            default = null;
                            description = "MatchLabels ensures an object with matching labels is selected.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      Selector to the resource.
                      This field will be ignored if ResourceRef is set.
                    '';
                  };
                };
              })
            );
            default = null;
            description = "By is the resource that is \"using the other resource\".";
          };
          of = mkOption {
            type = (
              mkTypedSubmodule {
                options = {
                  apiVersion = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = "API version of the referent.";
                  };
                  kind = mkOption {
                    type = (types.nullOr types.str);
                    default = null;
                    description = ''
                      Kind of the referent.
                      More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
                    '';
                  };
                  resourceRef = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          name = mkOption {
                            type = types.str;
                            description = "Name of the referent.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = "Reference to the resource.";
                  };
                  resourceSelector = mkOption {
                    type = (
                      types.nullOr (mkTypedSubmodule {
                        options = {
                          matchControllerRef = mkOption {
                            type = (types.nullOr types.bool);
                            default = null;
                            description = ''
                              MatchControllerRef ensures an object with the same controller reference
                              as the selecting object is selected.
                            '';
                          };
                          matchLabels = mkOption {
                            type = (types.nullOr (types.attrsOf types.str));
                            default = null;
                            description = "MatchLabels ensures an object with matching labels is selected.";
                          };
                        };
                      })
                    );
                    default = null;
                    description = ''
                      Selector to the resource.
                      This field will be ignored if ResourceRef is set.
                    '';
                  };
                };
              }
            );
            description = "Of is the resource that is \"being used\".";
          };
          reason = mkOption {
            type = (types.nullOr types.str);
            default = null;
            description = "Reason is the reason for blocking deletion of the resource.";
          };
          replayDeletion = mkOption {
            type = (types.nullOr types.bool);
            default = null;
            description = "ReplayDeletion will trigger a deletion on the used resource during the deletion of the usage itself, if it was attempted to be deleted at least once.";
          };
        };
      }
    );
  };

}
