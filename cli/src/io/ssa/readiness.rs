//! Waiting for the workloads a wave applied to actually roll out.

use std::fs;
use std::path::Path;

use anyhow::{Result, bail};
use console::style;

use super::tree::{wait_targets_in_file, yaml_files_under};

/// How to ask Kubernetes whether a workload is up.
///
/// Only Deployments carry an `Available` condition and only Jobs carry
/// `complete`; StatefulSets and DaemonSets carry neither, so a condition wait
/// on those blocks until the timeout however healthy they are.
pub(super) enum Readiness {
    Rollout,
    Condition(&'static str),
}

pub(super) fn readiness_for(kind: &str) -> Readiness {
    match kind {
        "Job" => Readiness::Condition("condition=complete"),
        _ => Readiness::Rollout,
    }
}

/// How many replicas a workload wants, when it can say.
fn desired_replicas(kube_context: &str, ns: &str, target: &str) -> Option<String> {
    let out = crate::io::process::run_capture(
        crate::io::kubectl::command()
            .args(["--context", kube_context, "-n", ns])
            .args(["get", target, "-o", "jsonpath={.spec.replicas}"]),
    )
    .ok()?;
    let n = out.trim().to_string();
    if n.is_empty() { None } else { Some(n) }
}

/// Whether this workload updates on delete rather than by rolling.
///
/// `kubectl rollout status` refuses outright on any strategy but
/// RollingUpdate, so asking it about one of these reports a healthy workload
/// as never having rolled out. openbao's StatefulSet is OnDelete, and its pod
/// was Running and Ready while the deploy failed on it.
fn updates_on_delete(kube_context: &str, ns: &str, target: &str) -> bool {
    crate::io::process::run_capture(
        crate::io::kubectl::command()
            .args(["--context", kube_context, "-n", ns])
            .args(["get", target, "-o", "jsonpath={.spec.updateStrategy.type}"]),
    )
    .map(|o| o.trim() == "OnDelete")
    .unwrap_or(false)
}

pub(super) fn wait_workloads_ready(
    kube_context: &str,
    phase_dir: &Path,
    timeout: &str,
) -> Result<()> {
    let mut targets: Vec<(String, String, String)> = Vec::new();
    for path in yaml_files_under(phase_dir) {
        let content = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        targets.extend(wait_targets_in_file(&content));
    }

    if targets.is_empty() {
        return Ok(());
    }

    println!(
        "{} Waiting for {} workload(s) in {} (timeout: {timeout})",
        style(">>>").cyan(),
        targets.len(),
        phase_dir.display(),
    );
    let mut stalled: Vec<String> = Vec::new();
    for (kind, ns, name) in &targets {
        let target = format!("{}/{name}", kind.to_lowercase());
        let (args, what): (Vec<String>, String) = match readiness_for(kind) {
            Readiness::Rollout if updates_on_delete(kube_context, ns, &target) => {
                let want =
                    desired_replicas(kube_context, ns, &target).unwrap_or_else(|| "1".into());
                (
                    vec![
                        "wait".to_string(),
                        format!("--for=jsonpath={{.status.readyReplicas}}={want}"),
                        target.clone(),
                        format!("--timeout={timeout}"),
                    ],
                    format!("have {want} ready replica(s)"),
                )
            }
            Readiness::Rollout => (
                vec![
                    "rollout".to_string(),
                    "status".to_string(),
                    target.clone(),
                    format!("--timeout={timeout}"),
                ],
                "finish rolling out".to_string(),
            ),
            Readiness::Condition(condition) => (
                vec![
                    "wait".to_string(),
                    format!("--for={condition}"),
                    target.clone(),
                    format!("--timeout={timeout}"),
                ],
                format!("reach {condition}"),
            ),
        };
        let result = crate::io::kubectl::command()
            .args(["--context", kube_context, "-n", ns])
            .args(&args)
            .status();
        match result {
            Ok(s) if s.success() => {}
            _ => {
                println!(
                    "{} {ns}/{target} did not {what} within {timeout}",
                    style("ERROR").red(),
                );
                stalled.push(format!("{ns}/{target}"));
            }
        }
    }

    if !stalled.is_empty() {
        bail!(
            "{} of {} workload(s) never became ready within {timeout}:\n  {}\n\
             `cata diagnose` shows their pods, events and logs.",
            stalled.len(),
            targets.len(),
            stalled.join("\n  "),
        );
    }
    Ok(())
}
