use anyhow::Result;
use console::style;

use crate::config::Context as CataContext;
use crate::io;

pub fn run(ctx: &CataContext) -> Result<()> {
    let name = ctx
        .flake_ref
        .fragment
        .as_deref()
        .ok_or_else(|| anyhow::anyhow!("No lab specified. Use --flake <ref>#<lab>"))?;

    let lab = crate::io::nix::get_lab_spec(ctx, name)?;

    println!(
        "{} Kubeconfig contexts for lab '{name}'",
        style("catallaxy").cyan().bold()
    );
    println!();

    for cluster_name in &lab.cluster_names {
        let context = lab.kube_context(cluster_name)?;
        let status = if io::kubectl::api_reachable(context) {
            style("reachable").green()
        } else {
            style("not reachable").yellow()
        };
        println!(
            "  {} → {} [{}]",
            style(cluster_name).cyan(),
            context,
            status
        );
    }

    Ok(())
}
