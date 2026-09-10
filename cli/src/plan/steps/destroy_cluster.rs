use anyhow::Result;
use console::style;

use crate::domain::plan::DestroyClusterParams;
use crate::domain::{ClusterSpec, ProvisionerKind, StepFailure};
use crate::io;
use crate::plan::StepContext;

pub fn run(sctx: &StepContext<'_>, p: &DestroyClusterParams) -> Result<()> {
    let DestroyClusterParams {
        name: cluster_name,
        provisioner: _,
        skip_if_missing,
    } = p;
    let skip_if_missing = skip_if_missing.unwrap_or(false);

    let mut step_failed = false;

    match sctx.lab.cluster(cluster_name) {
        Ok(spec) => {
            if skip_if_missing && k3d_already_gone(sctx, spec) {
                return Ok(());
            }
            if let Err(e) = crate::provision::deprovision_cluster(sctx.ctx, cluster_name, spec) {
                step_failed = true;
                println!(
                    "{} Failed to destroy '{}': {}",
                    style("ERROR").red(),
                    cluster_name,
                    e,
                );
            }
            if spec.provisioner == ProvisionerKind::K3d
                && !io::k3d::sweep_stragglers(k3d_name(spec))
            {
                step_failed = true;
            }
        }
        Err(e) => {
            step_failed = true;
            println!(
                "{} Failed to load config for '{}': {}",
                style("ERROR").red(),
                cluster_name,
                e,
            );
        }
    }

    if let Err(e) = crate::io::kubectl::cleanup_kubeconfig(cluster_name) {
        println!(
            "{} Failed to cleanup kubeconfig for '{}': {}",
            style("Warning:").yellow(),
            cluster_name,
            e,
        );
    }

    if step_failed {
        sctx.failures.borrow_mut().push(StepFailure::new(
            "destroy-cluster",
            format!("'{cluster_name}' was not confirmed destroyed"),
        ));
    }
    Ok(())
}

/// The k3d cluster name, empty for a cluster k3d did not make.
///
/// Both callers already guard on the provisioner, so the empty case is
/// unreachable. It stays a `&str` rather than an `Option` so the guard
/// remains the one place the provisioner is decided.
fn k3d_name(spec: &ClusterSpec) -> &str {
    spec.provisioner_config
        .k3d()
        .map_or("", |c| c.cluster_name.as_str())
}

fn k3d_already_gone(sctx: &StepContext<'_>, spec: &ClusterSpec) -> bool {
    if spec.provisioner != ProvisionerKind::K3d {
        return false;
    }
    let cluster_short = k3d_name(spec);
    let docker_host = crate::provision::resolve_docker_host(sctx.ctx, spec)
        .ok()
        .flatten();
    if io::k3d::cluster_exists(cluster_short, docker_host.as_deref()) {
        return false;
    }
    println!(
        "{} k3d cluster '{}' already gone; skipping",
        style(">>>").green(),
        cluster_short
    );
    true
}
