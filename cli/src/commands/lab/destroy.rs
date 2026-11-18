use anyhow::Result;

use crate::config::Context as CataContext;
use crate::plan::{Direction, execute};

pub async fn run(
    ctx: &CataContext,
    name: &str,
    dry_run: bool,
    up_to: Option<&str>,
    infra: bool,
) -> Result<()> {
    execute(ctx, name, dry_run, Direction::Teardown, up_to, infra).await?;
    if !dry_run && up_to.is_none() {
        close_tunnels(ctx, name);
    }
    Ok(())
}

/// Close every tunnel this lab held to a remote container host, now that
/// nothing on the other end is left to reach.
fn close_tunnels(ctx: &CataContext, name: &str) {
    let Ok(lab) = crate::io::nix::get_lab_document(ctx, name) else {
        return;
    };
    let state_dir = crate::host::state::lab_state_dir(name);
    for target in lab.container_hosts().iter().filter_map(|h| h.ssh_target()) {
        crate::io::remote::close(&state_dir, &target);
    }
}
