/*
  The Kubernetes API, as `T`, from the OpenAPI spec itself.

      fromSpec { spec = builtins.fromJSON (builtins.readFile ./swagger.json); }
      -> { types; resolve; coreKinds; fallbacks; }

  Reads the pinned spec at evaluation time rather than generating Nix from it.
  The spec is 3.1 MB of JSON and `fromJSON` takes 35 ms; the 77,623 lines of
  Nix this replaces took 82 ms just to parse, and two thirds of the resources
  it defined had `specType = types.attrs` — no field checking at all below the
  top level.

  `JSONSchemaProps` is the one self-referential definition in 635, and Nix's
  laziness is what makes it free: `types.JSONSchemaProps` is a thunk that
  mentions itself, forced only as deep as a value being checked requires.

  What it cannot express is recorded in `fallbacks` rather than quietly
  becoming `T.any`, so the gap is a number somebody can watch instead of a
  property of the output.
*/
{ lib, T }:

{ spec }:

let
  definitions = spec.definitions or (throw "the OpenAPI spec has no `definitions`");

  # `io.k8s.api.apps.v1.Deployment` -> `Deployment`, for error messages.
  shortName = name: lib.last (lib.splitString "." name);

  refTarget = schema: lib.removePrefix "#/definitions/" (schema."$ref" or "");

  # Kinds `T` has no word for. Each is `T.any` *and* an entry in `fallbacks`.
  unexpressible = {
    "int-or-string" =
      "an int or a string, and `T` has no union of two primitives — a Quantity or a port that may be named";
    number = "a float, and `T` has only `int`";
  };

  fallbackList = lib.unique (
    lib.flatten (lib.mapAttrsToList (name: _: fallbacksIn [ name ] definitions.${name}) definitions)
  );

  # Every place the conversion gave up, with the path and the reason. Walks
  # the schema rather than the output, because the output cannot say why it is
  # `T.any`.
  fallbacksIn =
    path: schema:
    let
      here =
        if schema ? "$ref" then
          [ ]
        else if (schema.format or null) != null && unexpressible ? ${schema.format} then
          [
            {
              path = lib.concatStringsSep "." path;
              why = unexpressible.${schema.format};
            }
          ]
        else if (schema.type or null) == "number" then
          [
            {
              path = lib.concatStringsSep "." path;
              why = unexpressible.number;
            }
          ]
        else if schema ? allOf || schema ? anyOf || schema ? oneOf || schema ? not then
          [
            {
              path = lib.concatStringsSep "." path;
              why = "a JSON Schema combinator, which only the CRD meta-schema uses";
            }
          ]
        else
          [ ];

      inner =
        lib.optionals (schema ? items) (fallbacksIn (path ++ [ "items" ]) schema.items)
        ++ lib.optionals (lib.isAttrs (schema.additionalProperties or null)) (
          fallbacksIn (path ++ [ "additionalProperties" ]) schema.additionalProperties
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (f: s: fallbacksIn (path ++ [ f ]) s) (schema.properties or { })
        );
    in
    here ++ inner;

  # The type of one schema node.
  convert =
    schema:
    let
      format = schema.format or null;
      type = schema.type or null;
    in
    if schema ? "$ref" then
      types.${refTarget schema}
      or (throw "the spec references `${refTarget schema}`, which it does not define")

    # A combinator, a float, or an int-or-string. `T` has no word for these;
    # `fallbacks` says where and why.
    else if
      schema ? allOf
      || schema ? anyOf
      || schema ? oneOf
      || schema ? not
      || unexpressible ? ${toString format}
    then
      T.any

    else if type == "string" then
      T.str
    else if type == "integer" then
      T.int
    else if type == "boolean" then
      T.bool
    else if type == "number" then
      T.any

    else if type == "array" then
      T.listOf (convert (schema.items or { }))

    else if type == "object" then
      let
        # A map, when the schema names no properties and says what the values
        # are. `additionalProperties: true` is an object with no shape at all.
        extra = schema.additionalProperties or null;
      in
      if !(schema ? properties) && lib.isAttrs extra then
        T.attrsOf (convert extra)
      else if !(schema ? properties) then
        T.any
      else
        let
          required = schema.required or [ ];
        in
        T.record (
          lib.mapAttrs (
            field: sub: if lib.elem field required then convert sub else T.optional (convert sub)
          ) schema.properties
        )

    # A definition with no `type` and no `$ref` carries only a description.
    else
      T.any;

  # Every definition, by its spec name, lazily. The recursion in
  # `JSONSchemaProps` resolves through this set.
  types = lib.mapAttrs (name: schema: T.named (shortName name) (convert schema)) definitions;

  # `x-kubernetes-group-version-kind` is the spec's own GVK table, so the
  # mapping from a resource's `apiVersion` and `kind` is read rather than
  # reconstructed from the definition's dotted name.
  gvkOf =
    name:
    map (g: {
      apiVersion = if (g.group or "") == "" then g.version else "${g.group}/${g.version}";
      inherit (g) kind;
      definition = name;
    }) (definitions.${name}."x-kubernetes-group-version-kind" or [ ]);

  gvks = lib.flatten (lib.mapAttrsToList (name: _: gvkOf name) definitions);

  byApiVersion = lib.foldl' (
    acc: g:
    acc
    // {
      ${g.apiVersion} = (acc.${g.apiVersion} or { }) // {
        ${g.kind} = g.definition;
      };
    }
  ) { } gvks;
in
{
  inherit types;

  /*
    The type for a resource's own `apiVersion` and `kind`, or null when the
    spec describes no such thing.

        resolve "apps/v1" "Deployment"   # => a T type
        resolve "nope.io/v1" "X"         # => null
  */
  resolve =
    apiVersion: kind:
    let
      definition = byApiVersion.${apiVersion}.${kind} or null;
    in
    if definition == null then null else types.${definition};

  # Every kind the apiserver serves, which is the membership question
  # `lib/lower/cluster.nix` asks and the only one that needs no field types.
  coreKinds = lib.unique (map (g: g.kind) gvks);

  # Where the conversion gave up, and why.
  fallbacks = fallbackList;
}
