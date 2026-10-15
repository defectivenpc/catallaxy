{ lib, crdTypes }:

let
  k8sTypes = import ./types.nix { inherit lib crdTypes; };
in
rec {
  /*
    The generated type for a resource's own `apiVersion` and `kind`, or null
    when nothing describes that kind.

    ```nix
    typeOf { apiVersion = "v1"; kind = "Secret"; }  # => a submodule type
    typeOf { apiVersion = "nope.io/v1"; kind = "X"; }  # => null
    ```
  */
  typeOf =
    resource:
    let
      av = resource.apiVersion or null;
      kind = resource.kind or null;
    in
    if av == null || kind == null then
      null
    else
      k8sTypes.generatedTypes.resolveResourceType k8sTypes.typesByKind av kind;

  /*
    The resource unchanged, once it has been checked against the schema its own
    `apiVersion` and `kind` name.

    Validation rather than substitution. Typing a floe's `resources` option
    would replace the resource with every field its schema declares, so a field
    nobody set would arrive as `null`: `r ? field` starts answering true for
    fields that are not there, `r.field or default` yields `null` instead of
    the default, and a resource stops comparing equal to the constructor that
    built it. The module system does the checking either way; only the value
    differs.

    A failure is an evaluation error naming the option path and the offending
    value — `spec.replicas = "three"` says so here, rather than being refused
    by the apiserver or silently pruned.

    A kind no generated schema describes passes unchecked. That is not a
    decision about the kind, it is the absence of one, and the `crd-coverage`
    check is what makes it visible.

    ```nix
    checked {
      apiVersion = "trust.cert-manager.io/v1alpha1";
      kind = "Bundle";
      metadata.name = "lab-ca";
      spec.sources = [ { secret = { name = "s"; key = "tls.crt"; }; } ];
    }
    => the same attrset
    ```
  */
  checked =
    resource:
    let
      t = typeOf resource;
    in
    if resource ? status then
      throw ''
        resource '${resource.metadata.name or "?"}' (${resource.apiVersion or "?"}/${resource.kind or "?"}) writes `status`.

        `status` belongs to whatever controller reconciles the object. A floe
        writes desired state; the apiserver discards a status sent with an
        apply, so this would read as configuration and do nothing.
      ''
    else if t == null then
      resource
    else
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            { options.resource = lib.mkOption { type = t; }; }
            { inherit resource; }
          ];
        }).config.resource
        resource;
}
