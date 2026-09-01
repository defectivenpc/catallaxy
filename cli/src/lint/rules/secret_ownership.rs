//! An ExternalSecret whose target is a Secret something else already renders.
//!
//! external-secrets defaults to `creationPolicy: Owner`. Where the target
//! already exists, the controller does not merge into it — it takes ownership
//! and rewrites the contents to exactly what it was told to produce. Every
//! other key in that Secret is gone, and nothing reports it: the apply
//! succeeded, the ExternalSecret reports `SecretSynced`, and the Secret is
//! there with the right name.
//!
//! What it looks like instead is a workload crash-looping on a credential it
//! was configured to read. `homelab.local` spent 600s waiting on `harbor-core`
//! with `password authentication failed for user "postgres"`: the floe
//! generated a `secret` key into a Secret called `harbor-core`, which is also
//! what the chart calls the Secret holding `POSTGRESQL_PASSWORD` and
//! `REGISTRY_CREDENTIAL_PASSWORD`. Three of harbor's six generated secrets
//! collided that way, and every chart with an `existingSecret` value can
//! reproduce it, because a name that reads as the obvious one is usually the
//! chart's too.

use std::collections::HashMap;

use serde_yaml::Value;

use crate::domain::diagnostic::{Diagnostic, Severity};

use crate::lint::manifest::K8sResource;

use super::{CheckContext, CheckRule};

pub struct SecretOwnership;

impl CheckRule for SecretOwnership {
    fn name(&self) -> &'static str {
        "secret-ownership"
    }
    fn check(&self, ctx: &CheckContext<'_>) -> Vec<Diagnostic> {
        check(ctx.resources, ctx.cluster)
    }
}

/// `(namespace, name)` of every Secret declared in the manifest set, mapped to
/// the resource that declares it.
fn declared_secrets(resources: &[K8sResource]) -> HashMap<(String, String), &K8sResource> {
    resources
        .iter()
        .filter(|r| r.kind == "Secret")
        .map(|r| ((r.namespace.clone().unwrap_or_default(), r.name.clone()), r))
        .collect()
}

/// The Secret an ExternalSecret writes: `spec.target.name`, defaulting to the
/// ExternalSecret's own name — which is the default that makes this easy to
/// hit, since it is invisible in the manifest.
fn target_of(r: &K8sResource) -> (String, bool) {
    let explicit = r
        .raw
        .get(Value::String("spec".into()))
        .and_then(|s| s.get(Value::String("target".into())))
        .and_then(|t| t.get(Value::String("name".into())))
        .and_then(|n| n.as_str())
        .map(String::from);

    match explicit {
        Some(name) => (name, true),
        None => (r.name.clone(), false),
    }
}

/// `creationPolicy`. Only `Owner` — the default — takes a Secret over.
/// `Merge` adds keys to one that exists, which is the whole point of it, and
/// `None` writes nothing at all.
fn takes_ownership(r: &K8sResource) -> bool {
    let policy = r
        .raw
        .get(Value::String("spec".into()))
        .and_then(|s| s.get(Value::String("target".into())))
        .and_then(|t| t.get(Value::String("creationPolicy".into())))
        .and_then(|p| p.as_str())
        .unwrap_or("Owner");

    policy == "Owner"
}

fn check(resources: &[K8sResource], cluster: &str) -> Vec<Diagnostic> {
    let secrets = declared_secrets(resources);
    let mut diags = Vec::new();

    for r in resources {
        if r.kind != "ExternalSecret" || !takes_ownership(r) {
            continue;
        }

        let namespace = r.namespace.clone().unwrap_or_default();
        let (target, explicit) = target_of(r);

        let Some(clobbered) = secrets.get(&(namespace.clone(), target.clone())) else {
            continue;
        };

        let keys = secret_keys(clobbered);
        let via = if explicit {
            "spec.target.name"
        } else {
            "its own name, since spec.target.name is unset"
        };

        diags.push(Diagnostic {
            severity: Severity::Error,
            check: "secret-ownership",
            cluster: cluster.to_string(),
            file: r.source_file.clone(),
            resource: r.display_id(),
            message: format!(
                "writes Secret '{namespace}/{target}' (by {via}), which is also rendered by \
                 {} carrying {keys}. creationPolicy Owner replaces the Secret's contents \
                 rather than merging, so those keys are deleted after the apply reports success. \
                 Point this at a name nothing else renders.",
                clobbered.source_file.display(),
            ),
        });
    }

    diags
}

fn secret_keys(r: &K8sResource) -> String {
    let mut names: Vec<&str> = ["data", "stringData"]
        .iter()
        .filter_map(|field| r.raw.get(Value::String((*field).into())))
        .filter_map(Value::as_mapping)
        .flat_map(|m| m.keys().filter_map(Value::as_str))
        .collect();

    if names.is_empty() {
        return "no keys".to_string();
    }
    names.sort_unstable();
    names.dedup();
    format!("[{}]", names.join(", "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn make_resource(yaml: &str) -> K8sResource {
        let value: Value = serde_yaml::from_str(yaml).unwrap();
        let mapping = value.as_mapping().unwrap();
        let meta = mapping
            .get(Value::String("metadata".into()))
            .and_then(Value::as_mapping);
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
            name: meta
                .and_then(|m| m.get(Value::String("name".into())))
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string(),
            namespace: meta
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

    fn chart_secret() -> K8sResource {
        make_resource(
            r#"
apiVersion: v1
kind: Secret
metadata:
  name: harbor-core
  namespace: harbor
data:
  POSTGRESQL_PASSWORD: cHc=
  REGISTRY_CREDENTIAL_PASSWORD: cHc=
"#,
        )
    }

    /// The harbor case, exactly.
    #[test]
    fn taking_over_a_chart_rendered_secret_is_an_error() {
        let es = make_resource(
            r#"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-core
  namespace: harbor
spec:
  target:
    name: harbor-core
"#,
        );

        let diags = check(&[chart_secret(), es], "core");
        assert_eq!(diags.len(), 1);
        assert_eq!(diags[0].severity, Severity::Error);
        assert!(diags[0].message.contains("harbor/harbor-core"));
        // It names what is lost, because that is what makes the report
        // actionable without opening the chart.
        assert!(diags[0].message.contains("POSTGRESQL_PASSWORD"));
    }

    /// The default is the trap: an ExternalSecret with no `spec.target.name`
    /// writes a Secret named after itself, and nothing in the manifest says so.
    #[test]
    fn the_implicit_target_counts_too() {
        let es = make_resource(
            r#"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-core
  namespace: harbor
spec:
  dataFrom:
    - sourceRef:
        generatorRef:
          kind: Password
"#,
        );

        let diags = check(&[chart_secret(), es], "core");
        assert_eq!(diags.len(), 1);
        assert!(diags[0].message.contains("spec.target.name is unset"));
    }

    /// A name nothing else renders is the whole fix, and it must read as clean.
    #[test]
    fn a_target_nothing_else_renders_is_fine() {
        let es = make_resource(
            r#"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-core
  namespace: harbor
spec:
  target:
    name: harbor-core-secret
"#,
        );

        assert!(check(&[chart_secret(), es], "core").is_empty());
    }

    /// Merging into an existing Secret is what `Merge` is for, and saying it
    /// is a collision would forbid the one policy that handles one.
    #[test]
    fn merge_is_not_a_collision() {
        let es = make_resource(
            r#"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-core
  namespace: harbor
spec:
  target:
    name: harbor-core
    creationPolicy: Merge
"#,
        );

        assert!(check(&[chart_secret(), es], "core").is_empty());
    }

    /// Same name, different namespace, different Secret.
    #[test]
    fn the_namespace_is_part_of_the_identity() {
        let es = make_resource(
            r#"
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: harbor-core
  namespace: other
spec:
  target:
    name: harbor-core
"#,
        );

        assert!(check(&[chart_secret(), es], "core").is_empty());
    }
}
