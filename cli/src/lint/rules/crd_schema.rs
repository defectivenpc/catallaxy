use std::collections::HashMap;

use serde_yaml::Value;

use crate::domain::diagnostic::{Diagnostic, Severity};

use crate::lint::manifest::K8sResource;

use super::{CheckContext, CheckRule};

pub struct CrdSchema;

impl CheckRule for CrdSchema {
    fn name(&self) -> &'static str {
        "crd-schema"
    }
    fn check(&self, ctx: &CheckContext<'_>) -> Vec<Diagnostic> {
        check(ctx.resources, ctx.cluster)
    }
}

fn check(resources: &[K8sResource], cluster: &str) -> Vec<Diagnostic> {
    let schemas = extract_crd_schemas(resources);
    if schemas.is_empty() {
        return Vec::new();
    }

    let mut diags = Vec::new();

    for r in resources {
        if r.is_crd() {
            continue;
        }

        let key = crd_key(&r.api_version, &r.kind);
        let schema = match schemas.get(&key) {
            Some(s) => s,
            None => continue,
        };

        validate_object(&r.raw, schema, "", r, cluster, &mut diags);
    }

    diags
}

pub(super) fn crd_key(api_version: &str, kind: &str) -> String {
    format!("{api_version}/{kind}")
}

/// Present on every object, declared by almost no CRD's `openAPIV3Schema`,
/// and never pruned. Reporting them as undeclared would fire on every custom
/// resource in the tree, which is how a rule gets turned off.
const API_SERVER_OWNED_FIELDS: [&str; 3] = ["apiVersion", "kind", "metadata"];

#[derive(Debug)]
pub(super) struct SchemaNode {
    schema_type: Option<String>,
    required: Vec<String>,
    properties: HashMap<String, SchemaNode>,
    items: Option<Box<SchemaNode>>,
    enum_values: Vec<String>,
    additional_properties: Option<Box<SchemaNode>>,

    /// `x-kubernetes-preserve-unknown-fields`. Where it is set, a field the
    /// schema does not declare is kept rather than pruned, so an unknown one
    /// is not an error and must not be reported as one.
    preserve_unknown: bool,
}

pub(super) fn extract_crd_schemas(resources: &[K8sResource]) -> HashMap<String, SchemaNode> {
    let mut schemas = HashMap::new();

    for r in resources {
        if !r.is_crd() {
            continue;
        }

        let mapping = match r.raw.as_mapping() {
            Some(m) => m,
            None => continue,
        };

        let spec = match mapping
            .get(Value::String("spec".into()))
            .and_then(|v| v.as_mapping())
        {
            Some(s) => s,
            None => continue,
        };

        let group = match spec
            .get(Value::String("group".into()))
            .and_then(|v| v.as_str())
        {
            Some(g) => g,
            None => continue,
        };

        let names = match spec
            .get(Value::String("names".into()))
            .and_then(|v| v.as_mapping())
        {
            Some(n) => n,
            None => continue,
        };

        let kind = match names
            .get(Value::String("kind".into()))
            .and_then(|v| v.as_str())
        {
            Some(k) => k,
            None => continue,
        };

        let versions = match spec
            .get(Value::String("versions".into()))
            .and_then(|v| v.as_sequence())
        {
            Some(v) => v,
            None => continue,
        };

        for version_entry in versions {
            let version_map = match version_entry.as_mapping() {
                Some(m) => m,
                None => continue,
            };

            let version_name = match version_map
                .get(Value::String("name".into()))
                .and_then(|v| v.as_str())
            {
                Some(n) => n,
                None => continue,
            };

            let openapi_schema = match version_map
                .get(Value::String("schema".into()))
                .and_then(|v| v.as_mapping())
                .and_then(|m| m.get(Value::String("openAPIV3Schema".into())))
            {
                Some(s) => s,
                None => continue,
            };

            let node = parse_schema_node(openapi_schema);
            let key = format!("{group}/{version_name}/{kind}");
            schemas.insert(key, node);
        }
    }

    schemas
}

fn parse_schema_node(value: &Value) -> SchemaNode {
    let mapping = match value.as_mapping() {
        Some(m) => m,
        None => {
            return SchemaNode {
                schema_type: None,
                required: Vec::new(),
                properties: HashMap::new(),
                items: None,
                enum_values: Vec::new(),
                additional_properties: None,
                preserve_unknown: false,
            };
        }
    };

    let schema_type = mapping
        .get(Value::String("type".into()))
        .and_then(|v| v.as_str())
        .map(String::from);

    let required = mapping
        .get(Value::String("required".into()))
        .and_then(|v| v.as_sequence())
        .map(|seq| {
            seq.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let properties = mapping
        .get(Value::String("properties".into()))
        .and_then(|v| v.as_mapping())
        .map(|props| {
            props
                .iter()
                .filter_map(|(k, v)| k.as_str().map(|k| (k.to_string(), parse_schema_node(v))))
                .collect()
        })
        .unwrap_or_default();

    let items = mapping
        .get(Value::String("items".into()))
        .map(|v| Box::new(parse_schema_node(v)));

    let enum_values = mapping
        .get(Value::String("enum".into()))
        .and_then(|v| v.as_sequence())
        .map(|seq| {
            seq.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let additional_properties = mapping
        .get(Value::String("additionalProperties".into()))
        .and_then(|v| {
            if v.is_bool() {
                None
            } else {
                Some(Box::new(parse_schema_node(v)))
            }
        });

    let preserve_unknown = mapping
        .get(Value::String("x-kubernetes-preserve-unknown-fields".into()))
        .and_then(Value::as_bool)
        .unwrap_or(false);

    SchemaNode {
        schema_type,
        required,
        properties,
        items,
        enum_values,
        additional_properties,
        preserve_unknown,
    }
}

fn validate_object(
    value: &Value,
    schema: &SchemaNode,
    path: &str,
    resource: &K8sResource,
    cluster: &str,
    diags: &mut Vec<Diagnostic>,
) {
    if let Some(ref expected_type) = schema.schema_type {
        let actual_type = yaml_type_name(value);
        let type_ok = match expected_type.as_str() {
            "object" => value.is_mapping() || value.is_null(),
            "array" => value.is_sequence() || value.is_null(),
            "string" => value.is_string() || value.is_null(),
            "integer" => value.is_i64() || value.is_u64() || value.is_null(),
            "number" => value.is_number() || value.is_null(),
            "boolean" => value.is_bool() || value.is_null(),
            _ => true,
        };
        if !type_ok {
            diags.push(Diagnostic {
                severity: Severity::Warning,
                check: "crd-schema",
                cluster: cluster.to_string(),
                file: resource.source_file.clone(),
                resource: resource.display_id(),
                message: format!(
                    "{}: expected type '{}', got '{}'",
                    field_path(path),
                    expected_type,
                    actual_type
                ),
            });
            return;
        }
    }

    if !schema.enum_values.is_empty()
        && let Some(s) = value.as_str()
        && !schema.enum_values.contains(&s.to_string())
    {
        diags.push(Diagnostic {
            severity: Severity::Error,
            check: "crd-schema",
            cluster: cluster.to_string(),
            file: resource.source_file.clone(),
            resource: resource.display_id(),
            message: format!(
                "{}: value '{}' not in allowed values [{}]",
                field_path(path),
                s,
                schema.enum_values.join(", ")
            ),
        });
    }

    if let Some(mapping) = value.as_mapping() {
        for req in &schema.required {
            if !mapping.contains_key(Value::String(req.clone())) {
                diags.push(Diagnostic {
                    severity: Severity::Error,
                    check: "crd-schema",
                    cluster: cluster.to_string(),
                    file: resource.source_file.clone(),
                    resource: resource.display_id(),
                    message: format!("{}: missing required field '{}'", field_path(path), req),
                });
            }
        }

        for (k, v) in mapping {
            if let Some(key) = k.as_str() {
                let child_path = if path.is_empty() {
                    key.to_string()
                } else {
                    format!("{path}.{key}")
                };

                if let Some(prop_schema) = schema.properties.get(key) {
                    validate_object(v, prop_schema, &child_path, resource, cluster, diags);
                } else if let Some(ref ap) = schema.additional_properties {
                    validate_object(v, ap, &child_path, resource, cluster, diags);
                } else if schema.preserve_unknown
                    || schema.properties.is_empty()
                    || (path.is_empty() && API_SERVER_OWNED_FIELDS.contains(&key))
                {
                    // Nothing to say. `preserve_unknown` means the API server
                    // keeps whatever is here; an empty `properties` means the
                    // CRD declared no shape at this level — `metadata` is
                    // usually the latter — and a schema that describes nothing
                    // cannot be violated. At the root, the three fields the
                    // API machinery supplies are present on every object and
                    // declared by almost no CRD.
                } else {
                    // A closed object, and this key is not in it. The API
                    // server prunes it under a normal apply and *rejects* the
                    // whole object under server-side apply, with
                    // "field not declared in schema" — which is a failed
                    // deploy, not a warning. This branch used to be absent, so
                    // the one error class this rule most obviously exists for
                    // was the one it stayed silent about.
                    diags.push(Diagnostic {
                        severity: Severity::Error,
                        check: "crd-schema",
                        cluster: cluster.to_string(),
                        file: resource.source_file.clone(),
                        resource: resource.display_id(),
                        message: format!(
                            "{}: field '{}' is not declared in the CRD schema (known: {})",
                            field_path(path),
                            key,
                            known_fields(schema)
                        ),
                    });
                }
            }
        }
    }

    if let Some(seq) = value.as_sequence()
        && let Some(ref items_schema) = schema.items
    {
        for (i, item) in seq.iter().enumerate() {
            let child_path = format!("{path}[{i}]");
            validate_object(item, items_schema, &child_path, resource, cluster, diags);
        }
    }
}
fn yaml_type_name(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "boolean",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Sequence(_) => "array",
        Value::Mapping(_) => "object",
        Value::Tagged(_) => "tagged",
    }
}

fn field_path(path: &str) -> &str {
    if path.is_empty() { "(root)" } else { path }
}

/// What the schema does declare here, so the diagnostic names the near miss
/// rather than only the wrong word. `version` against a CRD offering `image`
/// is the case this was written for.
fn known_fields(schema: &SchemaNode) -> String {
    let mut names: Vec<&str> = schema.properties.keys().map(String::as_str).collect();
    names.sort_unstable();
    names.join(", ")
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn make_resource(yaml: &str) -> K8sResource {
        let value: Value = serde_yaml::from_str(yaml).unwrap();
        let mapping = value.as_mapping().unwrap();
        K8sResource {
            api_version: mapping
                .get(Value::String("apiVersion".into()))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            kind: mapping
                .get(Value::String("kind".into()))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            name: mapping
                .get(Value::String("metadata".into()))
                .and_then(|v| v.as_mapping())
                .and_then(|m| m.get(Value::String("name".into())))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            namespace: mapping
                .get(Value::String("metadata".into()))
                .and_then(|v| v.as_mapping())
                .and_then(|m| m.get(Value::String("namespace".into())))
                .and_then(|v| v.as_str())
                .map(String::from),
            selector: None,
            pod_labels: None,
            configmap_refs: Vec::new(),
            secret_refs: Vec::new(),
            source_file: PathBuf::from("test.yaml"),
            raw: value,
            lint_skip: Vec::new(),
        }
    }

    #[test]
    fn test_crd_schema_missing_required_field() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required:
                - provider
              properties:
                provider:
                  type: string
                config:
                  type: object
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
  namespace: default
spec:
  config: {}
"#,
        );

        let diags = check(&[crd, resource], "test-cluster");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].severity, Severity::Error);
        assert!(
            diags[0]
                .message
                .contains("missing required field 'provider'")
        );
        assert!(diags[0].message.contains("spec"));
    }

    #[test]
    fn test_crd_schema_valid_resource() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required:
                - provider
              properties:
                provider:
                  type: string
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
  namespace: default
spec:
  provider: aws
"#,
        );

        let diags = check(&[crd, resource], "test-cluster");
        assert!(diags.is_empty());
    }

    #[test]
    fn test_crd_schema_invalid_enum() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                mode:
                  type: string
                  enum:
                    - fast
                    - slow
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
spec:
  mode: invalid
"#,
        );

        let diags = check(&[crd, resource], "test-cluster");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].severity, Severity::Error);
        assert!(diags[0].message.contains("not in allowed values"));
    }

    #[test]
    fn test_crd_schema_type_mismatch() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                replicas:
                  type: integer
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
spec:
  replicas: "not-a-number"
"#,
        );

        let diags = check(&[crd, resource], "test-cluster");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].severity, Severity::Warning);
        assert!(diags[0].message.contains("expected type 'integer'"));
    }

    /// The case this rule most obviously exists for, and the one it was
    /// silent about. `homelab.local` renders a `Kanidm` with `spec.version`
    /// against a kaniop CRD that declares `image`; lint said "all checks
    /// passed" and the apply died on
    /// `.spec.version: field not declared in schema`, thirty times over three
    /// minutes, before failing the deploy.
    #[test]
    fn a_field_the_crd_does_not_declare_is_an_error() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
spec:
  version: "1.6.4"
"#,
        );

        let diags = check(&[crd, resource], "test-cluster");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].severity, Severity::Error);
        assert!(diags[0].message.contains("'version' is not declared"));
        // And it names what the schema does have, so the near miss is visible
        // without opening the CRD.
        assert!(diags[0].message.contains("known: image"));
    }

    /// A schema that keeps what it does not declare is not violated by an
    /// undeclared field, and saying otherwise would make the rule unusable
    /// against every CRD carrying free-form configuration.
    #[test]
    fn preserve_unknown_fields_admits_anything() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              x-kubernetes-preserve-unknown-fields: true
              properties:
                image:
                  type: string
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
spec:
  anythingAtAll: yes
"#,
        );

        assert!(check(&[crd, resource], "test-cluster").is_empty());
    }

    /// A CRD that declares no shape at a level cannot be violated at it.
    /// `metadata` is almost always this, and reporting every label and
    /// annotation as undeclared would drown the rule.
    #[test]
    fn a_level_the_crd_describes_nothing_about_is_not_checked() {
        let crd = make_resource(
            r#"
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.io
spec:
  group: example.io
  names:
    kind: Widget
  versions:
    - name: v1
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
"#,
        );

        let resource = make_resource(
            r#"
apiVersion: example.io/v1
kind: Widget
metadata:
  name: test-widget
  labels:
    anything: here
spec:
  whatever: true
"#,
        );

        assert!(check(&[crd, resource], "test-cluster").is_empty());
    }
}
