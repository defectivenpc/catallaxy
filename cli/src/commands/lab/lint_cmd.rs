use std::path::PathBuf;

use anyhow::{Result, bail};
use console::style;

use crate::config::Context as CataContext;
use crate::io;
use crate::lint;

pub fn run(
    ctx: &CataContext,
    name: Option<String>,
    path: Option<PathBuf>,
    skip: Vec<String>,
) -> Result<()> {
    println!("{} Environment", style("catallaxy").cyan().bold(),);
    let tool_results = io::process::check_all_tools();
    let mut missing_tools = Vec::new();
    for (name, found, info) in &tool_results {
        if *found {
            println!("  {} {}", style("✓").green(), name);
        } else {
            println!("  {} {} ({})", style("✗").red(), name, info);
            missing_tools.push(name.as_str());
        }
    }
    println!();

    if !missing_tools.is_empty() {
        println!(
            "{} Missing tools: {}",
            style("Warning:").yellow(),
            missing_tools.join(", ")
        );
        println!();
    }

    let lab_name = match &path {
        Some(_) => None,
        None => Some(ctx.resolve_lab_name(name.as_deref())?),
    };

    if let Some(ref lab_name) = lab_name {
        println!("{} Configuration", style("catallaxy").cyan().bold());
        match crate::io::nix::get_lab_spec(ctx, lab_name) {
            Ok(lab) => {
                let cluster_names: Vec<&str> =
                    lab.cluster_names.iter().map(String::as_str).collect();
                let strategy = lab.cd.strategy.tag();

                println!("  {} lab: {}", style("✓").green(), lab_name);
                println!("  {} strategy: {}", style("✓").green(), strategy);
                println!(
                    "  {} clusters: {}",
                    style("✓").green(),
                    cluster_names.join(", ")
                );

                for cluster in &cluster_names {
                    match lab.cluster(cluster) {
                        Ok(spec) => {
                            let floe_count = spec.enabled_floes().count();
                            println!(
                                "    {} {} ({}, {} floes)",
                                style("✓").green(),
                                cluster,
                                format!("{:?}", spec.provisioner).to_lowercase(),
                                floe_count,
                            );
                        }
                        Err(e) => {
                            println!("    {} {}: {}", style("✗").red(), cluster, e,);
                        }
                    }
                }
            }
            Err(e) => {
                println!("  {} lab config failed: {}", style("✗").red(), e);
                bail!("Configuration validation failed");
            }
        }
        println!();
    }

    println!("{} Manifests", style("catallaxy").cyan().bold());
    let package_path = match path {
        Some(p) => p,
        None => {
            let lab_name =
                lab_name.expect("lab_name is Some whenever path is None (see binding above)");
            println!("  Building...");
            let store_path = crate::io::nix::build_lab_package(ctx, &lab_name)?;
            PathBuf::from(store_path)
        }
    };

    let passed = lint::run_lint(&package_path, &skip)?;

    if !passed {
        bail!("lint checks failed");
    }

    Ok(())
}
