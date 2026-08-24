//! JSON Schema to `NixType`, for both schema dialects this generates from.
//!
//! There were two of these: one for Kubernetes' OpenAPI definitions and one
//! for CRD `openAPIV3Schema` blocks. Their object handling was line-for-line
//! the same, and everything else was additive on one side or the other — so
//! each dialect silently lacked whatever the other had thought of. The CRD
//! path ignored `$ref`, `allOf` and `oneOf` (falling through to `types.attrs`,
//! which is "no schema at all"), and the OpenAPI path ignored
//! `x-kubernetes-preserve-unknown-fields`, which Kubernetes' own published
//! schemas do use.
//!
//! One converter, parameterised by whether there are definitions to resolve a
//! `$ref` against. A CRD has none, so a `$ref` there still resolves to
//! `types.attrs` — but by taking the same route, not by falling off the end.

use std::collections::BTreeMap;

use serde_json::Value;

use super::types::{GeneratorOptions, NixOption, NixType, Submodule};

pub struct Converter<'a> {
    options: &'a GeneratorOptions,
    definitions: &'a BTreeMap<String, Value>,
    /// The `$ref` chain currently being followed, so a definition that
    /// references itself resolves to `attrs` rather than recursing forever.
    visited_refs: Vec<String>,
}

/// Somewhere for a caller with no definitions to point at.
static NO_DEFINITIONS: std::sync::LazyLock<BTreeMap<String, Value>> =
    std::sync::LazyLock::new(BTreeMap::new);

impl<'a> Converter<'a> {
    pub fn new(options: &'a GeneratorOptions, definitions: &'a BTreeMap<String, Value>) -> Self {
        Self {
            options,
            definitions,
            visited_refs: Vec::new(),
        }
    }

    /// For a schema that stands alone, like a CRD's `openAPIV3Schema`.
    pub fn standalone(options: &'a GeneratorOptions) -> Self {
        Self::new(options, &NO_DEFINITIONS)
    }

    pub fn convert(&mut self, schema: &Value) -> NixType {
        if let Some(ref_path) = schema.get("$ref").and_then(|v| v.as_str()) {
            return self.convert_ref(ref_path);
        }

        // `allOf`/`oneOf`/`anyOf` describe a type only when there is no type
        // to describe. A CRD routinely carries them *beside* `properties`, as
        // a validation rule — "exactly one of these may be set" — and the
        // branches then hold required-key lists rather than alternatives.
        // Reading them first threw the real schema away: gateway-api's
        // `addresses[]` went from `{ type: str; value: str; }` with its
        // descriptions to `either <freeform> <freeform>`.
        let describes_itself = schema.get("type").is_some() || schema.get("properties").is_some();

        if !describes_itself {
            // Intersection, which Nix's module types cannot express, so the
            // first member stands in. Kubernetes uses it to hang a
            // description on a `$ref`.
            if let Some(all_of) = schema.get("allOf").and_then(|v| v.as_array())
                && let Some(first) = all_of.first()
            {
                return self.convert(first);
            }

            if let Some(one_of) = schema
                .get("oneOf")
                .or_else(|| schema.get("anyOf"))
                .and_then(|v| v.as_array())
            {
                let types: Vec<NixType> = one_of.iter().map(|s| self.convert(s)).collect();
                if types.len() == 2 {
                    return NixType::Either(Box::new(types[0].clone()), Box::new(types[1].clone()));
                } else if !types.is_empty() {
                    return NixType::OneOf(types);
                }
            }
        }

        match schema.get("type").and_then(|v| v.as_str()) {
            Some("string") => Self::convert_string(schema),
            Some("integer") => NixType::Int,
            Some("number") => NixType::Float,
            Some("boolean") => NixType::Bool,
            Some("array") => self.convert_array(schema),
            Some("object") => self.convert_object(schema),
            Some("null") => NixType::NullOr(Box::new(NixType::Anything)),
            // No `type` but properties is an object by implication, which is
            // how much of the CRD corpus is written.
            None if schema.get("properties").is_some() => self.convert_object(schema),
            _ => NixType::Anything,
        }
    }

    fn convert_string(schema: &Value) -> NixType {
        if let Some(enum_values) = schema.get("enum").and_then(|v| v.as_array()) {
            let values: Vec<String> = enum_values
                .iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect();
            if !values.is_empty() {
                return NixType::Enum(values);
            }
        }

        // `int-or-string` is the only format that changes the *type*.
        // `date-time`, `date`, `time`, `byte` and `binary` constrain what a
        // string may contain, which Nix's module system has no way to say, so
        // they fall through with everything else.
        match schema.get("format").and_then(|v| v.as_str()) {
            Some("int-or-string") => {
                NixType::Either(Box::new(NixType::Int), Box::new(NixType::Str))
            }
            _ => NixType::Str,
        }
    }

    fn convert_array(&mut self, schema: &Value) -> NixType {
        let inner = match schema.get("items") {
            Some(items) => self.convert(items),
            None => NixType::Anything,
        };
        NixType::ListOf(Box::new(inner))
    }

    fn convert_object(&mut self, schema: &Value) -> NixType {
        if let Some(additional) = schema.get("additionalProperties") {
            if additional.is_boolean() {
                if additional.as_bool() == Some(true) {
                    return NixType::Attrs;
                }
            } else {
                let value_type = self.convert(additional);
                return NixType::AttrsOf(Box::new(value_type));
            }
        }

        // A CRD saying it accepts fields it has not described. The submodule
        // still declares what it does describe, and takes the rest freeform.
        let preserve_unknown = schema
            .get("x-kubernetes-preserve-unknown-fields")
            .and_then(Value::as_bool)
            .unwrap_or(false);

        let Some(properties) = schema.get("properties").and_then(|v| v.as_object()) else {
            return NixType::Attrs;
        };

        let required: Vec<&str> = schema
            .get("required")
            .and_then(|v| v.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect())
            .unwrap_or_default();

        let mut submodule = Submodule::new();

        for (name, prop_schema) in properties {
            let prop_type = self.convert(prop_schema);
            let is_required = required.contains(&name.as_str());

            let mut option = NixOption::new(if is_required {
                prop_type
            } else {
                prop_type.nullable()
            });

            if !is_required {
                option.default = Some("null".to_string());
            }

            if self.options.include_descriptions
                && let Some(desc) = prop_schema.get("description").and_then(|v| v.as_str())
            {
                option.description = Some(desc.to_string());
            }

            submodule.options.insert(name.clone(), option);
        }

        if self.options.freeform_type || preserve_unknown {
            submodule.freeform_type = Some(Box::new(NixType::Attrs));
        }

        NixType::Submodule(submodule)
    }

    fn convert_ref(&mut self, ref_path: &str) -> NixType {
        let def_name = ref_path.strip_prefix("#/definitions/").unwrap_or(ref_path);

        if self.visited_refs.iter().any(|v| v == def_name) {
            return NixType::Attrs;
        }

        let Some(schema) = self.definitions.get(def_name).cloned() else {
            return NixType::Attrs;
        };

        self.visited_refs.push(def_name.to_string());
        let result = self.convert(&schema);
        self.visited_refs.pop();
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn convert_standalone(schema: &Value) -> NixType {
        let options = GeneratorOptions::default();
        Converter::standalone(&options).convert(schema)
    }

    #[test]
    fn a_string_with_an_enum_becomes_an_enum() {
        let t = convert_standalone(&json!({ "type": "string", "enum": ["Always", "Never"] }));
        assert!(matches!(t, NixType::Enum(v) if v == vec!["Always", "Never"]));
    }

    #[test]
    fn int_or_string_becomes_either() {
        let t = convert_standalone(&json!({ "type": "string", "format": "int-or-string" }));
        assert!(matches!(t, NixType::Either(..)));
    }

    #[test]
    fn a_format_that_only_constrains_contents_is_still_a_string() {
        let t = convert_standalone(&json!({ "type": "string", "format": "date-time" }));
        assert!(matches!(t, NixType::Str));
    }

    #[test]
    fn properties_without_a_type_are_still_an_object() {
        let t = convert_standalone(&json!({ "properties": { "a": { "type": "string" } } }));
        assert!(matches!(t, NixType::Submodule(_)));
    }

    #[test]
    fn a_required_property_is_not_nullable() {
        let t = convert_standalone(&json!({
            "type": "object",
            "properties": { "a": { "type": "string" }, "b": { "type": "string" } },
            "required": ["a"],
        }));
        let NixType::Submodule(s) = t else {
            panic!("expected a submodule");
        };
        assert!(matches!(s.options["a"].ty, NixType::Str));
        assert!(matches!(s.options["b"].ty, NixType::NullOr(_)));
        assert_eq!(s.options["b"].default.as_deref(), Some("null"));
    }

    /// The CRD path did not read this at all, so a CRD that accepts undeclared
    /// fields got a submodule that rejected them.
    #[test]
    fn preserve_unknown_fields_makes_the_submodule_freeform() {
        let t = convert_standalone(&json!({
            "type": "object",
            "x-kubernetes-preserve-unknown-fields": true,
            "properties": { "a": { "type": "string" } },
        }));
        let NixType::Submodule(s) = t else {
            panic!("expected a submodule");
        };
        assert!(s.freeform_type.is_some());
    }

    #[test]
    fn additional_properties_becomes_attrs_of() {
        let t = convert_standalone(&json!({
            "type": "object",
            "additionalProperties": { "type": "string" },
        }));
        assert!(matches!(t, NixType::AttrsOf(inner) if matches!(*inner, NixType::Str)));
    }

    /// A CRD has no definitions to resolve against, so a `$ref` is as much as
    /// can be said — but it goes through `convert_ref`, not off the end of the
    /// match.
    #[test]
    fn a_ref_with_nothing_to_resolve_against_is_attrs() {
        let t = convert_standalone(&json!({ "$ref": "#/definitions/io.k8s.Thing" }));
        assert!(matches!(t, NixType::Attrs));
    }

    #[test]
    fn a_ref_resolves_through_the_definitions() {
        let options = GeneratorOptions::default();
        let mut defs = BTreeMap::new();
        defs.insert("Thing".to_string(), json!({ "type": "integer" }));
        let t = Converter::new(&options, &defs).convert(&json!({ "$ref": "#/definitions/Thing" }));
        assert!(matches!(t, NixType::Int));
    }

    /// Kubernetes' schemas are full of self-referential definitions; without
    /// the visited set this recurses until the stack goes.
    #[test]
    fn a_self_referential_ref_terminates() {
        let options = GeneratorOptions::default();
        let mut defs = BTreeMap::new();
        defs.insert(
            "Node".to_string(),
            json!({
                "type": "object",
                "properties": { "child": { "$ref": "#/definitions/Node" } },
            }),
        );
        let t = Converter::new(&options, &defs).convert(&json!({ "$ref": "#/definitions/Node" }));
        let NixType::Submodule(s) = t else {
            panic!("expected a submodule");
        };
        assert!(matches!(s.options["child"].ty, NixType::NullOr(_)));
    }

    /// `allOf` is how Kubernetes attaches a description to a `$ref`, and it
    /// appears alone. The CRD path used to ignore it and yield `attrs`.
    #[test]
    fn all_of_takes_its_first_member() {
        let t = convert_standalone(&json!({ "allOf": [{ "type": "boolean" }] }));
        assert!(matches!(t, NixType::Bool));
    }

    #[test]
    fn two_alternatives_become_either() {
        let t = convert_standalone(&json!({
            "oneOf": [{ "type": "string" }, { "type": "integer" }],
        }));
        assert!(matches!(t, NixType::Either(..)));
    }

    /// A CRD carries `oneOf` beside `properties` as a validation rule — the
    /// branches list required keys, they are not alternative types. Reading
    /// them in preference to the schema turned gateway-api's `addresses[]`
    /// from two described strings into a union of two freeform submodules.
    #[test]
    fn a_combinator_beside_a_real_schema_does_not_replace_it() {
        let t = convert_standalone(&json!({
            "type": "object",
            "properties": { "value": { "type": "string" } },
            "oneOf": [{ "required": ["value"] }, { "required": ["other"] }],
        }));
        let NixType::Submodule(s) = t else {
            panic!("the properties must win, not the oneOf");
        };
        assert!(matches!(s.options["value"].ty, NixType::NullOr(_)));
    }

    #[test]
    fn a_combinator_beside_a_bare_type_does_not_replace_it() {
        let t = convert_standalone(&json!({
            "type": "string",
            "anyOf": [{ "format": "ipv4" }, { "format": "ipv6" }],
        }));
        assert!(matches!(t, NixType::Str));
    }
}
