{
  lib,
  floeCore,
  k8sApi,
}:

rec {

  typeOf =
    resource:
    let
      av = resource.apiVersion or null;
      kind = resource.kind or null;
    in
    if av == null || kind == null then null else k8sApi.resolve av kind;

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
      builtins.deepSeq (floeCore.conformValue [
        (resource.kind or "?")
        (resource.metadata.name or "?")
      ] t resource) resource;
}
