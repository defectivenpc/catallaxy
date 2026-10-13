{ lib }:

let
  inherit (lib) mkOption types;

  /*
    An object schema, closed unless its own declaration says otherwise.

    Closed is the default because an open one cannot tell a misspelling from a
    new field: `configMapp` becomes a key rather than an error and reaches the
    apiserver, which prunes it silently under a structural schema. The
    generator passes `freeformType` explicitly for the schemas Kubernetes marks
    `x-kubernetes-preserve-unknown-fields`, which are open by declaration and
    stay that way.
  */
  mkTypedSubmodule =
    {
      options,
      freeformType ? null,
    }:
    types.submodule (
      { inherit options; } // lib.optionalAttrs (freeformType != null) { inherit freeformType; }
    );

  /*
    A resource, closed like everything else.

    `topLevel` is the kind's other authorable fields, from the same schema
    `specType` comes from: `Role.rules`, `RoleBinding.roleRef` and `subjects`,
    `Secret.type`. The top level used to be freeform because only `spec` was
    converted, which left a misspelled `metadataa` reading as a new key.

    `status` is declared by nothing, on purpose, so writing one is refused: it
    is the controller's, and a floe writes desired state. A resource that
    genuinely needs a field no schema describes goes out through a bundle's
    `yamls` instead.
  */
  mkResource =
    {
      apiVersion,
      kind,
      specType ? types.attrs,
      topLevel ? { },
    }:
    mkTypedSubmodule {
      options = topLevel // {
        apiVersion = mkOption {
          type = types.str;
          default = apiVersion;
          description = "Kubernetes API version";
        };

        kind = mkOption {
          type = types.str;
          default = kind;
          description = "Kubernetes resource kind";
        };

        metadata = mkOption {
          type = mkTypedSubmodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Resource name";
              };
              namespace = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Resource namespace";
              };
              labels = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "Resource labels";
              };
              annotations = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "Resource annotations";
              };
            };
          };
          description = "Resource metadata";
        };

        spec = mkOption {
          type = types.nullOr specType;
          default = null;
          description = "Resource specification";
        };
      };
    };
in
{
  inherit mkTypedSubmodule mkResource;
}
