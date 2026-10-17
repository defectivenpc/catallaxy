//! The document's shape, as a `floes` type for Nix to check against.
//!
//! `cata` parses the document into real Rust types, so those types are what
//! the shape *is*. This turns them into the `T` vocabulary the floe linker
//! speaks, so the half that produces a document is held to the same shape as
//! the half that reads one — from one definition rather than two that agree
//! until they don't.
//!
//! Reads `schemars` output rather than the types directly, because that is
//! derived: a field added to `LabSpec` changes the schema with no edit here.

use std::collections::BTreeMap;

use anyhow::{Context, Result, bail};
use serde_json::Value;

/// A JSON Schema definition name (`LabSpec`) as a Nix binding (`labSpec`).
fn binding(name: &str) -> String {
    let mut chars = name.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// `{"$ref": "#/$defs/LabSpec"}` -> `LabSpec`.
fn ref_target(schema: &Value) -> Option<&str> {
    schema.get("$ref")?.as_str()?.strip_prefix("#/$defs/")
}

/// A rendered type as a function argument.
///
/// `T.attrsOf (T.listOf T.str)` and not `T.attrsOf T.listOf T.str`, which Nix
/// reads as applying `attrsOf` to three arguments.
fn as_arg(rendered: String) -> String {
    if rendered.contains(' ') {
        format!("({rendered})")
    } else {
        rendered
    }
}

/// Whether a schema is the `null` type, which is how `Option` renders.
fn is_null(schema: &Value) -> bool {
    schema.get("type").and_then(Value::as_str) == Some("null")
}

/// The type of a JSON Schema node, in `T`.
///
/// Total over what `schemars` emits for the document: every arm below is
/// reached by some field of `LabSpec`, and anything else is an error rather
/// than a guess, because a silent `T.any` is how a shape stops describing the
/// value.
fn render(schema: &Value) -> Result<String> {
    // `serde_json::Value` carries no shape, so it reflects as a schema with
    // nothing constraining in it — sometimes bare, sometimes with only a
    // `default` beside it, which is what `#[serde(default)] pub x: Value`
    // emits. Annotations do not make a shape.
    const CONSTRAINING: [&str; 8] = [
        "type",
        "$ref",
        "enum",
        "anyOf",
        "oneOf",
        "allOf",
        "properties",
        "additionalProperties",
    ];
    if schema.as_bool() == Some(true)
        || schema
            .as_object()
            .is_some_and(|o| !CONSTRAINING.iter().any(|k| o.contains_key(*k)))
    {
        return Ok("T.any".into());
    }

    if let Some(target) = ref_target(schema) {
        return Ok(binding(target));
    }

    // `Option<T>` where T is a reference or a union: `anyOf [T, null]`.
    if let Some(any_of) = schema.get("anyOf").and_then(Value::as_array) {
        let inner: Vec<&Value> = any_of.iter().filter(|s| !is_null(s)).collect();
        if any_of.iter().any(is_null) && inner.len() == 1 {
            return Ok(format!("T.nullOr {}", as_arg(render(inner[0])?)));
        }
        bail!(
            "anyOf with {} non-null branches is not a type `T` has",
            inner.len()
        );
    }

    // An externally tagged enum with data: exactly `T.taggedUnion`.
    if let Some(one_of) = schema.get("oneOf").and_then(Value::as_array) {
        let mut variants = Vec::new();
        for variant in one_of {
            let props = variant
                .get("properties")
                .and_then(Value::as_object)
                .with_context(|| format!("oneOf branch is not a tagged object: {variant}"))?;
            let (tag, inner) = props
                .iter()
                .next()
                .context("a tagged union branch with no tag")?;
            variants.push(format!("{tag} = {};", render(inner)?));
        }
        return Ok(format!("T.taggedUnion {{ {} }}", variants.join(" ")));
    }

    // A unit-variant enum, or a single-valued constant.
    if let Some(values) = schema.get("enum").and_then(Value::as_array) {
        let names: Result<Vec<String>> = values
            .iter()
            .map(|v| {
                v.as_str()
                    .map(|s| format!("\"{s}\""))
                    .context("an enum value that is not a string")
            })
            .collect();
        return Ok(format!("T.enum [ {} ]", names?.join(" ")));
    }

    // `Option<primitive>` renders as a type *list* rather than an `anyOf`.
    if let Some(types) = schema.get("type").and_then(Value::as_array) {
        let named: Vec<&str> = types.iter().filter_map(Value::as_str).collect();
        let inner: Vec<&&str> = named.iter().filter(|t| **t != "null").collect();
        if named.contains(&"null") && inner.len() == 1 {
            let mut bare = schema.clone();
            bare["type"] = Value::String((*inner[0]).to_string());
            return Ok(format!("T.nullOr {}", as_arg(render(&bare)?)));
        }
        bail!("a union of {named:?} is not a type `T` has");
    }

    let ty = schema
        .get("type")
        .and_then(Value::as_str)
        .with_context(|| format!("a schema with no `type`, `$ref`, `enum` or union: {schema}"))?;

    match ty {
        "string" => Ok("T.str".into()),
        "integer" | "number" => Ok("T.int".into()),
        "boolean" => Ok("T.bool".into()),

        "array" => {
            let items = schema.get("items").context("an array with no `items`")?;
            Ok(format!("T.listOf {}", as_arg(render(items)?)))
        }

        "object" => render_object(schema),

        other => bail!("`{other}` is not a type `T` has"),
    }
}

/// The object arm of [`render`]: a map, a record, or an unconstrained blob.
fn render_object(schema: &Value) -> Result<String> {
    // A map, which is how `BTreeMap` reflects.
    if let Some(values) = schema.get("additionalProperties")
        && schema.get("properties").is_none()
    {
        return Ok(format!("T.attrsOf {}", as_arg(render(values)?)));
    }

    let props = schema
        .get("properties")
        .and_then(Value::as_object)
        .map(|o| o.iter().collect::<BTreeMap<_, _>>())
        .unwrap_or_default();

    if props.is_empty() {
        return Ok("T.any".into());
    }

    // A field the parser tolerates missing is `T.optional`, not `T.nullOr`:
    // absent and null are different values, and the producer does omit these
    // — 23 of the document's 48 definitions have at least one.
    let required: Vec<&str> = schema
        .get("required")
        .and_then(Value::as_array)
        .map(|r| r.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default();

    let mut fields = Vec::new();
    for (name, field) in props {
        let rendered = render(field)?;
        let rendered = if required.contains(&name.as_str()) {
            rendered
        } else {
            format!("T.optional {}", as_arg(rendered))
        };
        fields.push(format!("      {name} = {rendered};"));
    }
    Ok(format!("T.record {{\n{}\n    }}", fields.join("\n")))
}

/// The lab document's shape, as `floes` type source.
///
/// Takes no schema: the module knows which types it describes, so there is no
/// way to call it with the wrong one.
pub fn lab_document() -> Result<String> {
    let schema = schemars::schema_for!(crate::domain::lab::LabSpec);
    let json = serde_json::to_value(&schema).context("serialising the document schema")?;
    emit(&json).context("emitting the document type")
}

/// The whole generated file.
///
/// One `rec` set of every named definition, because the references between
/// them are a graph rather than a tree — `ClusterSpec` reaches `Content`,
/// which reaches `WaveBundle` — and `rec` is what lets the emitted order not
/// matter.
fn emit(schema: &Value) -> Result<String> {
    let title = schema
        .get("title")
        .and_then(Value::as_str)
        .context("the schema has no `title` to name the document after")?;

    let defs = schema
        .get("$defs")
        .and_then(Value::as_object)
        .context("the schema has no `$defs`")?;

    let mut out = String::new();
    out.push_str(
        "# Generated by `cata-build document`. Do not edit.\n\
         #\n\
         # The shape `cata` parses a lab document into, as a `floes` type. The Rust\n\
         # types in `cli/src/domain/` are the definition; this is them in the\n\
         # vocabulary the linker checks a floe's output against.\n\
         { T }:\n\
         \n\
         let\n\
         \x20 defs = rec {\n",
    );

    for (name, def) in defs {
        out.push_str(&format!(
            "    {} = T.named \"{}\" (\n      {}\n    );\n\n",
            binding(name),
            name,
            render(def)
                .with_context(|| format!("rendering `{name}`"))?
                .replace('\n', "\n  ")
        ));
    }

    // The document itself joins the `rec` set rather than being rendered
    // after it, so the definitions it refers to are in scope by name.
    out.push_str(&format!(
        "    {} = T.named \"{}\" (\n      {}\n    );\n",
        binding(title),
        title,
        render(schema)
            .context("rendering the document")?
            .replace('\n', "\n  ")
    ));

    out.push_str(&format!("  }};\nin\ndefs.{}\n", binding(title)));

    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_map_of_records_is_an_attrs_of_a_record() {
        let s = json!({
            "type": "object",
            "additionalProperties": { "$ref": "#/$defs/HostService" }
        });
        assert_eq!(render(&s).unwrap(), "T.attrsOf hostService");

        // Nested applications need the parentheses, or Nix reads one call
        // with three arguments.
        let nested = json!({
            "type": "object",
            "additionalProperties": { "type": "array", "items": { "type": "string" } }
        });
        assert_eq!(render(&nested).unwrap(), "T.attrsOf (T.listOf T.str)");
    }

    #[test]
    fn an_optional_primitive_is_a_null_or() {
        let s = json!({ "type": ["integer", "null"] });
        assert_eq!(render(&s).unwrap(), "T.nullOr T.int");
    }

    #[test]
    fn an_optional_reference_is_a_null_or() {
        let s = json!({ "anyOf": [ { "$ref": "#/$defs/DnsInfo" }, { "type": "null" } ] });
        assert_eq!(render(&s).unwrap(), "T.nullOr dnsInfo");
    }

    #[test]
    fn a_field_the_parser_tolerates_missing_is_optional() {
        let s = json!({
            "type": "object",
            "properties": { "repo": { "type": "string" }, "branch": { "type": "string" } },
            "required": ["repo"]
        });
        let out = render(&s).unwrap();
        assert!(out.contains("repo = T.str;"), "{out}");
        assert!(out.contains("branch = T.optional T.str;"), "{out}");
    }

    #[test]
    fn a_unit_enum_is_an_enum() {
        let s = json!({ "enum": ["sops", "env"] });
        assert_eq!(render(&s).unwrap(), "T.enum [ \"sops\" \"env\" ]");
    }

    #[test]
    fn an_externally_tagged_enum_is_a_tagged_union() {
        let s = json!({
            "oneOf": [
                { "type": "object", "properties": { "k3d": { "$ref": "#/$defs/K3dConfig" } } },
                { "type": "object", "properties": { "talos": { "$ref": "#/$defs/TalosConfig" } } }
            ]
        });
        assert_eq!(
            render(&s).unwrap(),
            "T.taggedUnion { k3d = k3dConfig; talos = talosConfig; }"
        );
    }

    /// `serde_json::Value` carries no shape, and saying so is better than
    /// inventing one.
    #[test]
    fn an_unconstrained_schema_is_any() {
        assert_eq!(render(&json!(true)).unwrap(), "T.any");
        assert_eq!(render(&json!({})).unwrap(), "T.any");

        // `#[serde(default)] pub x: Value` — an annotation and no shape.
        assert_eq!(render(&json!({ "default": null })).unwrap(), "T.any");
        assert_eq!(
            render(&json!({ "description": "a free-form blob" })).unwrap(),
            "T.any"
        );
    }

    /// A construct `T` has no word for fails rather than degrading to `any`,
    /// because a shape that silently stops describing the value is the whole
    /// thing this exists to prevent.
    #[test]
    fn a_construct_t_lacks_is_refused() {
        let s = json!({ "type": "object", "properties": { "x": { "type": "integer", "format": "ip" } } });
        assert!(render(&s).is_ok());

        let bad = json!({ "anyOf": [ { "type": "string" }, { "type": "integer" } ] });
        assert!(render(&bad).is_err());
    }
}
