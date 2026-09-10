use anyhow::{Context, Result};
use serde_json::Value;

use super::types::{GeneratorOptions, K8sResourceType};

pub fn parse_crds_from_yaml(
    yaml: &str,
    options: &GeneratorOptions,
) -> Result<Vec<K8sResourceType>> {
    let mut resources = Vec::new();

    for doc in yaml_rust2::YamlLoader::load_from_str(yaml).context("Failed to parse YAML")? {
        let value = yaml_to_json(&doc)?;

        let kind = value.get("kind").and_then(|v| v.as_str());

        if kind == Some("CustomResourceDefinition") {
            if let Some(crd) = parse_single_crd(&value, options)? {
                resources.push(crd);
            }
        } else if kind == Some("List")
            && let Some(items) = value.get("items").and_then(|v| v.as_array())
        {
            for item in items {
                if item.get("kind").and_then(|v| v.as_str()) == Some("CustomResourceDefinition")
                    && let Some(crd) = parse_single_crd(item, options)?
                {
                    resources.push(crd);
                }
            }
        }
    }

    Ok(resources)
}

fn parse_single_crd(crd: &Value, options: &GeneratorOptions) -> Result<Option<K8sResourceType>> {
    let spec = crd.get("spec").context("CRD missing spec")?;

    let group = spec
        .get("group")
        .and_then(|v| v.as_str())
        .context("CRD missing group")?;
    let kind = spec
        .get("names")
        .and_then(|n| n.get("kind"))
        .and_then(|v| v.as_str())
        .context("CRD missing kind")?;

    if options.exclude_groups.iter().any(|g| group.contains(g)) {
        return Ok(None);
    }

    let versions = spec.get("versions").and_then(|v| v.as_array());
    let version_info = if let Some(versions) = versions {
        versions
            .iter()
            .find(|v| v.get("storage").and_then(|s| s.as_bool()).unwrap_or(false))
            .or_else(|| {
                versions
                    .iter()
                    .find(|v| v.get("served").and_then(|s| s.as_bool()).unwrap_or(true))
            })
            .or_else(|| versions.first())
    } else {
        None
    };

    let version = version_info
        .and_then(|v| v.get("name").and_then(|n| n.as_str()))
        .or_else(|| spec.get("version").and_then(|v| v.as_str()))
        .unwrap_or("v1");

    let mut resource =
        K8sResourceType::new(group.to_string(), version.to_string(), kind.to_string());

    let schema = version_info
        .and_then(|v| v.get("schema"))
        .and_then(|s| s.get("openAPIV3Schema"))
        .or_else(|| {
            spec.get("validation")
                .and_then(|v| v.get("openAPIV3Schema"))
        });

    if let Some(schema) = schema {
        if let Some(spec_schema) = schema.get("properties").and_then(|p| p.get("spec")) {
            resource.spec =
                Some(super::convert::Converter::standalone(options).convert(spec_schema));
        }

        if options.include_descriptions {
            resource.description = schema
                .get("description")
                .and_then(|v| v.as_str())
                .map(String::from);
        }
    }

    resource.namespaced = spec
        .get("scope")
        .and_then(|v| v.as_str())
        .map(|s| s == "Namespaced")
        .unwrap_or(true);

    Ok(Some(resource))
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_crd() {
        let yaml = r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: certificates.cert-manager.io
spec:
  group: cert-manager.io
  names:
    kind: Certificate
    plural: certificates
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                secretName:
                  type: string
                issuerRef:
                  type: object
                  properties:
                    name:
                      type: string
                    kind:
                      type: string
"#;

        let options = GeneratorOptions::default();
        let crds = parse_crds_from_yaml(yaml, &options).unwrap();

        assert_eq!(crds.len(), 1);
        assert_eq!(crds[0].kind, "Certificate");
        assert_eq!(crds[0].group, "cert-manager.io");
        assert_eq!(crds[0].version, "v1");
    }
}
