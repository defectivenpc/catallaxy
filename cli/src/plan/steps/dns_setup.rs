use anyhow::Result;
use console::style;

use crate::domain::plan::DnsSetupParams;
use crate::host::dns;
use crate::plan::StepContext;

pub fn run(sctx: &StepContext<'_>, p: &DnsSetupParams) -> Result<()> {
    let DnsSetupParams { host, port, zone } = p;
    if sctx.lab.host.ssh_target().is_some() {
        println!(
            "{} The lab is on a remote host, so this machine's resolver is left alone; \
             `cata lab attach` reaches its names instead.",
            style(">>>").yellow(),
        );
        return Ok(());
    }

    if sctx.dry_run {
        println!(
            "{} [dry-run] would point host DNS for '{}' at {}:{}",
            style(">>>").yellow(),
            zone,
            host,
            port,
        );
        return Ok(());
    }
    dns::dns_setup(host, *port, zone)
}
