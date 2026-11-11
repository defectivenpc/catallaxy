use anyhow::{Context, Result};
use console::style;

use crate::domain::lab::LabDns;
use crate::domain::plan::RegistrySetupParams;
use crate::host::registry;
use crate::plan::StepContext;

pub fn run(sctx: &StepContext<'_>, p: &RegistrySetupParams) -> Result<()> {
    let RegistrySetupParams {
        port,
        upstreams,
        zone: _,
    } = p;

    if sctx.dry_run {
        println!(
            "{} [dry-run] would write registries.yaml, certs.d/, and lab-resolv.conf",
            style(">>>").yellow()
        );
        return Ok(());
    }

    let port = u16::try_from(*port).with_context(|| {
        format!(
            "lab.registry.port is {port}, which is not a TCP port (1-65535). \
             Truncating it would have written a registries.yaml pointing at a \
             different, plausible-looking port"
        )
    })?;

    let dns = LabDns::resolve(sctx.lab, crate::io::docker::first_network_ip);

    registry::write_node_config(
        sctx.lab_name,
        port,
        upstreams,
        sctx.lab.registry_trust_zone(),
        &dns,
    )?;
    Ok(())
}
