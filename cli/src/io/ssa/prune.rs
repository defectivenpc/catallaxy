//! Removing what the declaration stopped naming, and letting go of the
//! fields this field manager used to own.

use std::collections::BTreeSet;
use std::path::Path;

use anyhow::Result;
use console::style;

use crate::domain::prune::{PruneInputs, plan_prune};
use crate::io;

use super::ApplyManifests;
use super::tree::{WaveMeta, applied_resources, declared_bundles, yaml_files_under};

/// Delete what the declaration stopped naming.
///
/// Runs after every wave, not per wave: a resource can move between bundles,
/// and pruning mid-apply would delete it before the bundle that now owns it
/// had a chance to apply it.
pub(super) fn prune_undeclared(
    opts: &ApplyManifests<'_>,
    meta: &WaveMeta,
    manifest_root: &Path,
) -> Result<()> {
    let &ApplyManifests {
        kube_context,
        dry_run,
        lab_name,
        ..
    } = opts;

    // No file means a tree rendered before pruning existed. Deleting on that
    // basis would treat every bundle as undeclared, so say nothing and do
    // nothing.
    let Some(declared) = declared_bundles(manifest_root) else {
        return Ok(());
    };

    let applied_bundles: BTreeSet<String> = meta
        .waves
        .iter()
        .flat_map(|w| w.bundles.iter().map(|b| b.key.clone()))
        .collect();

    let kubectl = io::kubectl::seam::Real;
    let live = io::kubectl::owned::owned_by_lab(&kubectl, kube_context, lab_name)?;
    let plan = plan_prune(PruneInputs {
        live: &live,
        declared_bundles: &declared,
        applied_bundles: &applied_bundles,
        applied: &applied_resources(manifest_root),
    });

    if plan.is_empty() {
        return Ok(());
    }

    for key in &plan.delete {
        if dry_run {
            println!(
                "{} Would remove {}, which the lab no longer declares",
                style(">>>").yellow(),
                key.describe(),
            );
            continue;
        }
        println!(
            "{} Removing {}, which the lab no longer declares",
            style(">>>").cyan(),
            key.describe(),
        );
        io::kubectl::owned::delete(&kubectl, kube_context, key)?;
    }

    if !plan.orphaned_storage.is_empty() {
        println!();
        println!(
            "{} The lab no longer declares these, and they hold data, so they \
             were left alone:",
            style("note:").yellow(),
        );
        for key in &plan.orphaned_storage {
            println!("      {}", key.describe());
        }
        println!(
            "      A lab that comes back finds its data. Remove them with \
             `kubectl delete` when you are sure."
        );
    }

    if !plan.unattributed.is_empty() {
        println!();
        println!(
            "{} These carry this lab's label but name no bundle, so nothing \
             can say whether the lab still wants them:",
            style("note:").yellow(),
        );
        for key in &plan.unattributed {
            println!("      {}", key.describe());
        }
    }

    Ok(())
}

/// Drop this field manager's ownership of the fields it applied, so a later
/// owner takes them without a conflict.
///
/// # Errors
///
/// Never. A manifest that cannot be read, and a release that fails, are both
/// skipped: the caller's next step is argocd taking over, and a field still
/// owned makes that a conflict argocd reports, not a reason to fail here. The
/// count actually released is printed.
pub fn relinquish_field_manager(
    kube_context: &str,
    manifest_root: &Path,
    field_manager: &str,
    dry_run: bool,
) -> Result<()> {
    if !manifest_root.exists() {
        return Ok(());
    }
    let files = yaml_files_under(manifest_root);
    if files.is_empty() {
        return Ok(());
    }
    if dry_run {
        println!(
            "{} Would release '{field_manager}' field ownership across {} manifest file(s)",
            style(">>>").yellow(),
            files.len(),
        );
        return Ok(());
    }

    let mut released = 0usize;
    for file in &files {
        let out = crate::io::kubectl::command()
            .args([
                "--context",
                kube_context,
                "get",
                "-f",
                &file.display().to_string(),
                "-o",
                "json",
                "--show-managed-fields",
                "--ignore-not-found",
            ])
            .output();
        let Ok(out) = out else { continue };
        if !out.status.success() {
            continue;
        }
        let Ok(doc) = serde_json::from_slice::<serde_json::Value>(&out.stdout) else {
            continue;
        };
        let items: Vec<&serde_json::Value> = match doc.get("items").and_then(|i| i.as_array()) {
            Some(arr) => arr.iter().collect(),
            None if doc.is_object() => vec![&doc],
            _ => continue,
        };
        for item in items {
            if release_one(kube_context, item, field_manager) {
                released += 1;
            }
        }
    }
    if released > 0 {
        println!(
            "{} Released '{field_manager}' field ownership on {released} resource(s); argocd now applies uncontested",
            style(">>>").green(),
        );
    }
    Ok(())
}

fn release_one(kube_context: &str, item: &serde_json::Value, field_manager: &str) -> bool {
    let Some(kind) = item.get("kind").and_then(|k| k.as_str()) else {
        return false;
    };
    let Some(meta) = item.get("metadata") else {
        return false;
    };
    let Some(name) = meta.get("name").and_then(|n| n.as_str()) else {
        return false;
    };
    let Some(fields) = meta.get("managedFields").and_then(|f| f.as_array()) else {
        return false;
    };
    let idx = fields.iter().position(|f| {
        f.get("manager").and_then(|m| m.as_str()) == Some(field_manager)
            && f.get("operation").and_then(|o| o.as_str()) == Some("Apply")
    });
    let Some(idx) = idx else { return false };

    let patch = serde_json::json!([
        { "op": "test", "path": format!("/metadata/managedFields/{idx}/manager"), "value": field_manager },
        { "op": "remove", "path": format!("/metadata/managedFields/{idx}") },
    ])
    .to_string();

    let mut args: Vec<String> = vec![
        "--context".into(),
        kube_context.into(),
        "patch".into(),
        kind.to_ascii_lowercase(),
        name.into(),
    ];
    if let Some(ns) = meta.get("namespace").and_then(|n| n.as_str()) {
        args.push("-n".into());
        args.push(ns.into());
    }
    args.extend(["--type".into(), "json".into(), "-p".into(), patch]);

    crate::io::kubectl::command()
        .args(&args)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
