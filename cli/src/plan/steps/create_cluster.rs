use anyhow::{Result, bail};

use crate::domain::plan::CreateClusterParams;
use crate::domain::{ClusterSpec, ProvisionerConfig};
use crate::host::state;
use crate::plan::StepContext;

/// Where the containerd config a node pulls through was written, or `None` for
/// a cluster that does not mirror.
///
/// Read off the cluster's own record. It used to be
/// `service_state_dir(lab, "registry")` joined from a literal and probed with
/// `.exists()`, so whether a cluster mirrored was decided by the filesystem at
/// deploy: a stale directory mounted a mirror nobody asked for, and a cluster
/// whose `registry-setup` had not run mounted none without a word.
///
/// Missing now is an error rather than a skip. The declaration is what says a
/// cluster mirrors, `registry-setup` runs before any cluster is created, and
/// a node that silently pulls from upstream is a lab that is slow for reasons
/// nobody can see.
fn node_config(sctx: &StepContext<'_>, spec: &ClusterSpec) -> Result<Option<std::path::PathBuf>> {
    let ProvisionerConfig::K3d(k3d) = &spec.provisioning.config else {
        return Ok(None);
    };
    let Some(service) = k3d.node_config_from.as_deref() else {
        return Ok(None);
    };

    let path = state::service_state_dir(sctx.lab_name, service).join("registries.yaml");
    if !path.exists() {
        bail!(
            "cluster '{}' pulls through the lab's '{service}' mirror and {} is not there.              `registry-setup` writes it and runs before any cluster is created, so either              that step did not run or its state directory was removed.",
            spec.cluster_handle.name,
            path.display(),
        );
    }
    Ok(Some(path))
}

pub fn run(sctx: &StepContext<'_>, p: &CreateClusterParams) -> Result<()> {
    let CreateClusterParams {
        name,
        provisioner: _,
    } = p;

    let spec = sctx.lab.cluster(name)?;

    let registries_yaml = node_config(sctx, spec)?;

    crate::provision::provision_cluster_with_registry(
        sctx.ctx,
        name,
        spec,
        registries_yaml.as_deref(),
        Some(sctx.lab_package),
    )?;

    if sctx.lab.services.contains_key("proxy") {
        crate::host::pki::import_lab_ca(sctx.lab_name, sctx.lab, name)?;
    }

    Ok(())
}
