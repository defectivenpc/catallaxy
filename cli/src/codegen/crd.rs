//! A CRD's schema, as the CRD carries it.
//!
//! Nix has no `fromYAML`, so this is the one format change generation has to
//! perform. The `openAPIV3Schema` goes over untouched and
//! `lib/kubernetes/schema-to-type.nix` converts it — the same path the
//! Kubernetes API takes.

use anyhow::{Context, Result};
use serde_json::Value;

fn yaml_to_json(yaml: &yaml_rust2::Yaml) -> Result<Value> {
    match yaml {
        yaml_rust2::Yaml::Null => Ok(Value::Null),
        yaml_rust2::Yaml::Boolean(b) => Ok(Value::Bool(*b)),
        yaml_rust2::Yaml::Integer(i) => Ok(Value::Number((*i).into())),
        yaml_rust2::Yaml::Real(s) => {
            let f: f64 = s.parse().context("Failed to parse float")?;
            Ok(serde_json::Number::from_f64(f)
                .map(Value::Number)
                .unwrap_or(Value::Null))
        }
        yaml_rust2::Yaml::String(s) => Ok(Value::String(s.clone())),
        yaml_rust2::Yaml::Array(arr) => {
            let values: Result<Vec<Value>> = arr.iter().map(yaml_to_json).collect();
            Ok(Value::Array(values?))
        }
        yaml_rust2::Yaml::Hash(hash) => {
            let mut map = serde_json::Map::new();
            for (k, v) in hash {
                let key = match k {
                    yaml_rust2::Yaml::String(s) => s.clone(),
                    yaml_rust2::Yaml::Integer(i) => i.to_string(),
                    other => format!("{other:?}"),
                };
                map.insert(key, yaml_to_json(v)?);
            }
            Ok(Value::Object(map))
        }
        yaml_rust2::Yaml::Alias(_) => Ok(Value::Null),
        yaml_rust2::Yaml::BadValue => Ok(Value::Null),
    }
}

/// Every CRD in a YAML stream as `kind -> { apiVersion, schema }`, with the
/// schema exactly as the CRD carries it.
///
/// A CRD's `openAPIV3Schema` is already JSON Schema, so handing it over
/// untouched lets Nix convert it with the same `T` converter the Kubernetes
/// API goes through. The only thing generation buys here is the format change
/// Nix forces: there is no `fromYAML`.
pub fn crd_schemas_from_yaml(yaml: &str) -> Result<serde_json::Map<String, Value>> {
    let mut out = serde_json::Map::new();

    let docs = yaml_rust2::YamlLoader::load_from_str(yaml).context("Failed to parse YAML")?;

    let mut consider = |value: &Value| -> Result<()> {
        if value.get("kind").and_then(Value::as_str) != Some("CustomResourceDefinition") {
            return Ok(());
        }

        let spec = value.get("spec").context("a CRD with no `spec`")?;
        let group = spec
            .get("group")
            .and_then(Value::as_str)
            .context("a CRD with no `spec.group`")?;
        let kind = spec
            .get("names")
            .and_then(|n| n.get("kind"))
            .and_then(Value::as_str)
            .context("a CRD with no `spec.names.kind`")?;

        // The stored version is the one a cluster persists, so it is the one a
        // resource written today is checked against.
        let versions = spec.get("versions").and_then(Value::as_array);
        let chosen = versions.and_then(|vs| {
            vs.iter()
                .find(|v| v.get("storage").and_then(Value::as_bool).unwrap_or(false))
                .or_else(|| {
                    vs.iter()
                        .find(|v| v.get("served").and_then(Value::as_bool).unwrap_or(true))
                })
                .or_else(|| vs.first())
        });

        let version = chosen
            .and_then(|v| v.get("name"))
            .and_then(Value::as_str)
            .or_else(|| spec.get("version").and_then(Value::as_str))
            .unwrap_or("v1");

        let schema = chosen
            .and_then(|v| v.get("schema"))
            .and_then(|s| s.get("openAPIV3Schema"))
            .or_else(|| {
                spec.get("validation")
                    .and_then(|v| v.get("openAPIV3Schema"))
            });

        if let Some(schema) = schema {
            out.insert(
                kind.to_string(),
                serde_json::json!({
                    "apiVersion": format!("{group}/{version}"),
                    "schema": schema,
                }),
            );
        }

        Ok(())
    };

    for doc in docs {
        let value = yaml_to_json(&doc)?;

        if value.get("kind").and_then(Value::as_str) == Some("List") {
            if let Some(items) = value.get("items").and_then(Value::as_array) {
                for item in items {
                    consider(item)?;
                }
            }
        } else {
            consider(&value)?;
        }
    }

    Ok(out)
}
