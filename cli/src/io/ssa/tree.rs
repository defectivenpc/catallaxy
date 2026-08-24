//! Reading the rendered manifest tree: what it declares, and what in it
//! needs waiting on.
//!
//! Split out of `mod.rs`, which was over the file-size limit and mixed this
//! with the apply state machine and the pruning pass.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use crate::domain::prune::ResourceKey;

use super::probe::ReadyProbe;

pub fn read_wave_meta(manifest_dir: &Path) -> Option<WaveMeta> {
    let raw = fs::read_to_string(manifest_dir.join(".wave-meta")).ok()?;
    serde_json::from_str(&raw).ok()
}

#[derive(serde::Deserialize, Debug)]
pub struct WaveMeta {
    pub waves: Vec<Wave>,
}

#[derive(serde::Deserialize, Debug)]
pub struct Wave {
    pub index: usize,
    pub bundles: Vec<WaveBundle>,
}

#[derive(serde::Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct WaveBundle {
    pub key: String,
    pub dir: String,
    #[serde(default)]
    pub ready_probe: Option<ReadyProbe>,
    pub has_content: bool,
    #[serde(default)]
    pub requires: Vec<String>,
    #[serde(default)]
    pub provides: Vec<String>,
}

/// Every `.yaml`/`.yml` file under `dir`, in a stable order.
///
/// Sorted because `read_dir` is not: two runs over the same tree otherwise
/// wait on workloads and release field ownership in different orders, which
/// makes a log diff between runs unreadable for no reason.
pub(super) fn yaml_files_under(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for entry in fs::read_dir(dir).into_iter().flatten().flatten() {
        let path = entry.path();
        if path.is_dir() {
            out.extend(yaml_files_under(&path));
        } else if path.extension().is_some_and(|e| e == "yaml" || e == "yml") {
            out.push(path);
        }
    }
    out.sort();
    out
}

const AWAIT_ROLLOUT: &str = "catallaxy.io/await-rollout";

/// Every resource the applied tree declares, as the cluster would name it.
pub(super) fn applied_resources(manifest_root: &Path) -> BTreeSet<ResourceKey> {
    let mut out = BTreeSet::new();
    for path in yaml_files_under(manifest_root) {
        let Ok(content) = fs::read_to_string(&path) else {
            continue;
        };
        for doc in serde_yaml::Deserializer::from_str(&content) {
            let Ok(value) = <serde_yaml::Value as serde::Deserialize>::deserialize(doc) else {
                continue;
            };
            let (Some(kind), Some(metadata)) = (
                value.get("kind").and_then(|k| k.as_str()),
                value.get("metadata"),
            ) else {
                continue;
            };
            let Some(name) = metadata.get("name").and_then(|n| n.as_str()) else {
                continue;
            };
            out.insert(ResourceKey::new(
                kind,
                metadata.get("namespace").and_then(|n| n.as_str()),
                name,
            ));
        }
    }
    out
}

/// Bundles the cluster declares, whoever applies them.
///
/// Written by the renderer because only the declaration knows it. The applied
/// tree is a subset -- for an argocd lab, just the install-target set -- so it
/// cannot tell a bundle that was dropped from one argocd owns.
pub(super) fn declared_bundles(manifest_root: &Path) -> Option<BTreeSet<String>> {
    let raw = fs::read_to_string(manifest_root.join(".declared-bundles")).ok()?;
    Some(
        raw.lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(String::from)
            .collect(),
    )
}

fn wait_target_in_value(doc: &serde_yaml::Value) -> Option<(String, String, String)> {
    let kind = doc.get("kind")?.as_str()?.to_string();
    if !matches!(
        kind.as_str(),
        "Deployment" | "StatefulSet" | "DaemonSet" | "Job"
    ) {
        return None;
    }

    let metadata = doc.get("metadata")?;

    let opted_out = metadata
        .get("annotations")
        .and_then(|a| a.get(AWAIT_ROLLOUT))
        .is_some_and(|v| match v {
            serde_yaml::Value::Bool(b) => !*b,
            other => other.as_str() == Some("false"),
        });
    if opted_out {
        return None;
    }

    let name = metadata.get("name")?.as_str()?.to_string();
    let namespace = metadata
        .get("namespace")
        .and_then(|n| n.as_str())
        .unwrap_or("default")
        .to_string();

    Some((kind, namespace, name))
}

pub(super) fn wait_targets_in_file(content: &str) -> Vec<(String, String, String)> {
    use serde::Deserialize;

    serde_yaml::Deserializer::from_str(content)
        .filter_map(|doc| serde_yaml::Value::deserialize(doc).ok())
        .filter_map(|doc| wait_target_in_value(&doc))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::io::ssa::readiness::{Readiness, readiness_for};

    fn wait_target_in_doc(doc: &str) -> Option<(String, String, String)> {
        let parsed: serde_yaml::Value = serde_yaml::from_str(doc).ok()?;
        wait_target_in_value(&parsed)
    }

    fn deployment(annotations: &str) -> String {
        format!(
            "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  annotations:{annotations}\n  labels: {{}}\n  name: netbird-agent\n  namespace: netbird\nspec:\n  replicas: 1\n"
        )
    }

    #[test]
    fn collects_an_ordinary_workload() {
        let target = wait_target_in_doc(&deployment(" {}")).expect("waited on");
        assert_eq!(
            target,
            (
                "Deployment".to_string(),
                "netbird".to_string(),
                "netbird-agent".to_string()
            )
        );
    }

    #[test]
    fn skips_a_workload_marked_await_rollout_false() {
        let doc = deployment("\n    catallaxy.io/await-rollout: \"false\"");
        assert!(wait_target_in_doc(&doc).is_none());
    }

    #[test]
    fn await_rollout_true_is_still_waited_on() {
        let doc = deployment("\n    catallaxy.io/await-rollout: \"true\"");
        assert!(wait_target_in_doc(&doc).is_some());
    }

    // Only Deployments have an Available condition and only Jobs have
    // complete. Waiting on a condition a kind never reports blocks until the
    // timeout no matter how healthy the workload is, which is what a
    // StatefulSet did for ten minutes before failing a deploy.
    #[test]
    fn the_controllers_are_asked_about_their_rollout_not_a_condition() {
        for kind in ["Deployment", "StatefulSet", "DaemonSet"] {
            assert!(
                matches!(readiness_for(kind), Readiness::Rollout),
                "{kind} should be waited on with `rollout status`"
            );
        }
    }

    #[test]
    fn a_job_is_asked_whether_it_completed() {
        assert!(matches!(
            readiness_for("Job"),
            Readiness::Condition("condition=complete")
        ));
    }

    #[test]
    fn ignores_kinds_that_have_no_rollout() {
        let doc = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cm\n  namespace: x\n";
        assert!(wait_target_in_doc(doc).is_none());
    }

    // A bundle whose only workload is a Job used to be waited on for nothing:
    // Job was not in the list of kinds, so the next wave started immediately.
    #[test]
    fn a_job_is_a_workload() {
        let doc = "apiVersion: batch/v1\nkind: Job\nmetadata:\n  name: bootstrap-ab12\n  namespace: forgejo\n";
        assert_eq!(
            wait_target_in_doc(doc).expect("a Job is work the next wave depends on"),
            (
                "Job".to_string(),
                "forgejo".to_string(),
                "bootstrap-ab12".to_string()
            )
        );
    }

    #[test]
    fn four_space_indentation_is_still_a_workload() {
        let doc = "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n    name: wide\n    namespace: team\n";
        assert_eq!(
            wait_target_in_doc(doc).expect("indentation is not the schema"),
            (
                "Deployment".to_string(),
                "team".to_string(),
                "wide".to_string()
            )
        );
    }

    #[test]
    fn the_opt_out_annotation_only_counts_on_the_workload_itself() {
        let configmap_quoting_the_annotation = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cm\ndata:\n  note: |\n    catallaxy.io/await-rollout: \"false\"\n";
        let doc = format!(
            "{configmap_quoting_the_annotation}---\n{}",
            deployment(" {}")
        );

        let targets = wait_targets_in_file(&doc);

        assert_eq!(
            targets.len(),
            1,
            "a ConfigMap that merely mentions the annotation must not disable the wait: {targets:?}"
        );
    }

    #[test]
    fn a_separator_inside_a_block_scalar_does_not_split_the_document() {
        let doc = format!(
            "apiVersion: v1\nkind: Secret\nmetadata:\n  name: tls\nstringData:\n  cert: |\n    -----BEGIN CERTIFICATE-----\n    aaa\n    ---\n    bbb\n    -----END CERTIFICATE-----\n---\n{}",
            deployment(" {}")
        );

        let targets = wait_targets_in_file(&doc);

        assert_eq!(
            targets,
            vec![(
                "Deployment".to_string(),
                "netbird".to_string(),
                "netbird-agent".to_string()
            )],
            "a --- inside a block scalar is data, not a document separator"
        );
    }

    #[test]
    fn an_unquoted_false_opts_out_too() {
        let doc = deployment("\n    catallaxy.io/await-rollout: false");
        assert!(wait_target_in_doc(&doc).is_none());
    }
}
