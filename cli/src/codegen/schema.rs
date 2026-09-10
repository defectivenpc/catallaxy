use std::collections::BTreeMap;

use anyhow::{Context, Result};
use serde::Deserialize;
use serde_json::Value;

use super::convert::Converter;
use super::types::{GeneratorOptions, K8sResourceType, K8sTypeSet};

#[derive(Debug, Deserialize)]
pub struct OpenApiSpec {
    pub definitions: BTreeMap<String, Value>,
    #[serde(default)]
    pub paths: BTreeMap<String, Value>,
    #[serde(default)]
    pub info: OpenApiInfo,
}

#[derive(Debug, Deserialize, Default)]
pub struct OpenApiInfo {
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub version: String,
}

pub fn parse_openapi_spec(json: &str) -> Result<OpenApiSpec> {
    serde_json::from_str(json).context("Failed to parse OpenAPI spec")
}

pub fn convert_openapi_to_types(
    spec: &OpenApiSpec,
    version: &str,
    options: &GeneratorOptions,
) -> K8sTypeSet {
    let mut type_set = K8sTypeSet::new(version);
    let mut converter = Converter::new(options, &spec.definitions);

    for (name, schema) in &spec.definitions {
        if should_skip_definition(name, options) {
            continue;
        }

        if let Some(gvk) = extract_gvk(schema) {
            let resource = convert_resource(&mut converter, schema, &gvk, options);
            type_set.add_resource(resource);
        }

        let nix_type = converter.convert(schema);
        type_set.add_definition(name.clone(), nix_type);
    }

    type_set
}

fn should_skip_definition(name: &str, options: &GeneratorOptions) -> bool {
    for excluded in &options.exclude_groups {
        if name.contains(excluded) {
            return true;
        }
    }
    false
}

fn extract_gvk(schema: &Value) -> Option<GroupVersionKind> {
    let gvk_array = schema.get("x-kubernetes-group-version-kind")?;
    let gvk = gvk_array.as_array()?.first()?;

    Some(GroupVersionKind {
        group: gvk.get("group")?.as_str()?.to_string(),
        version: gvk.get("version")?.as_str()?.to_string(),
        kind: gvk.get("kind")?.as_str()?.to_string(),
    })
}

#[derive(Debug)]
struct GroupVersionKind {
    group: String,
    version: String,
    kind: String,
}

/// One definition, as the resource type the emitter writes out.
///
/// The schema walking itself lives in `super::convert`, shared with the CRD
/// path; this is only the Kubernetes-resource framing around it.
fn convert_resource(
    converter: &mut Converter<'_>,
    schema: &Value,
    gvk: &GroupVersionKind,
    options: &GeneratorOptions,
) -> K8sResourceType {
    let mut resource =
        K8sResourceType::new(gvk.group.clone(), gvk.version.clone(), gvk.kind.clone());

    if options.include_descriptions {
        resource.description = schema
            .get("description")
            .and_then(|v| v.as_str())
            .map(String::from);
    }

    if let Some(properties) = schema.get("properties")
        && let Some(spec_schema) = properties.get("spec")
    {
        resource.spec = Some(converter.convert(spec_schema));
    }

    resource.namespaced = true;

    resource
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Schema walking itself is tested in `super::convert`; what is left here
    /// is the Kubernetes framing around it.
    #[test]
    fn a_definition_carrying_a_gvk_is_recognised() {
        let gvk = extract_gvk(&json!({
            "x-kubernetes-group-version-kind": [
                { "group": "apps", "version": "v1", "kind": "Deployment" }
            ],
        }))
        .expect("a well-formed gvk");
        assert_eq!(gvk.group, "apps");
        assert_eq!(gvk.version, "v1");
        assert_eq!(gvk.kind, "Deployment");
    }

    #[test]
    fn a_definition_without_a_gvk_is_not_a_resource() {
        assert!(extract_gvk(&json!({ "type": "object" })).is_none());
    }

    /// A partial gvk is not a resource. Taking it would emit a type with an
    /// empty group or kind, which the emitter would happily write out.
    #[test]
    fn a_partial_gvk_is_refused() {
        assert!(
            extract_gvk(&json!({
                "x-kubernetes-group-version-kind": [{ "group": "apps", "version": "v1" }],
            }))
            .is_none()
        );
    }

    #[test]
    fn an_excluded_group_is_skipped() {
        let options = GeneratorOptions {
            exclude_groups: vec!["io.k8s.kubernetes.pkg".to_string()],
            ..GeneratorOptions::default()
        };
        assert!(should_skip_definition(
            "io.k8s.kubernetes.pkg.apis.apps.v1.Deployment",
            &options
        ));
        assert!(!should_skip_definition(
            "io.k8s.api.apps.v1.Deployment",
            &options
        ));
    }

    #[test]
    fn a_resource_takes_its_spec_from_the_schema() {
        let options = GeneratorOptions::default();
        let defs = BTreeMap::new();
        let mut converter = Converter::new(&options, &defs);
        let gvk = GroupVersionKind {
            group: "apps".to_string(),
            version: "v1".to_string(),
            kind: "Deployment".to_string(),
        };
        let resource = convert_resource(
            &mut converter,
            &json!({
                "properties": { "spec": { "type": "object", "properties": { "replicas": { "type": "integer" } } } },
            }),
            &gvk,
            &options,
        );
        assert!(resource.spec.is_some());
        assert_eq!(resource.kind, "Deployment");
    }
}
