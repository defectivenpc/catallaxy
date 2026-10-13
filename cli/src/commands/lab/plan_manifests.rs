use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use console::style;
use serde_json::Value;

use crate::config::Context as CataContext;
use crate::domain::WaveBundle;

use super::golden;

pub fn run(
    ctx: &CataContext,
    name: Option<&str>,
    cluster: Option<&str>,
    stable: bool,
    from_file: Option<PathBuf>,
    diff: Option<PathBuf>,
) -> Result<()> {
    let stable = stable || diff.is_some();

    let waves = load_waves(ctx, name, cluster, from_file.as_deref())?;

    if stable {
        let text = format_stable(&waves);
        if let Some(baseline) = diff {
            if !golden::run_diff(&text, &baseline, "manifest waves")? {
                return Err(crate::domain::ExitWith(1).into());
            }
            return Ok(());
        }
        print!("{text}");
        return Ok(());
    }

    render_pretty(name.unwrap_or(""), cluster.unwrap_or(""), &waves);
    Ok(())
}

fn load_waves(
    ctx: &CataContext,
    name: Option<&str>,
    cluster: Option<&str>,
    from_file: Option<&Path>,
) -> Result<Vec<Vec<WaveBundle>>> {
    if let Some(path) = from_file {
        let raw = crate::io::fs::read_to_string(path)
            .with_context(|| format!("reading manifest-waves file {}", path.display()))?;
        let v: Value = serde_json::from_str(&raw)
            .with_context(|| format!("parsing JSON from {}", path.display()))?;
        return extract_waves(&v, cluster).with_context(|| {
            format!(
                "reading the wave summary from {} (expected a `[[bundle]]` array, or a lab document whose `clusters.<name>.content.waves` holds one)",
                path.display()
            )
        });
    }

    let lab_name =
        name.ok_or_else(|| anyhow::anyhow!("lab name is required unless --from-file is set"))?;
    let lab = crate::io::nix::get_lab_document(ctx, lab_name)?;
    extract_waves(&lab, cluster).with_context(|| {
        format!(
            "reading the wave summary for lab '{lab_name}' cluster '{}'",
            cluster.unwrap_or("<any>")
        )
    })
}

/// The waves for one cluster, out of whatever was handed over.
///
/// Three shapes, because `--from-file` is how the golden test feeds a wave
/// list without evaluating a lab: a bare `[[bundle]]`, a whole lab document,
/// or a lab document with one cluster named. Typed through `WaveBundle` in
/// every case, which is what makes the summary's fields read rather than
/// dug out of a `Value` by key beside a struct nothing used.
fn extract_waves(v: &Value, cluster: Option<&str>) -> Result<Vec<Vec<WaveBundle>>> {
    if v.is_array() {
        return serde_json::from_value(v.clone())
            .context("expected `[[bundle]]`, with each bundle a wave summary entry");
    }

    let clusters = v
        .get("clusters")
        .and_then(|v| v.as_object())
        .ok_or_else(|| anyhow::anyhow!("no `clusters` object in JSON, cannot resolve waves"))?;

    let (name, value) = match cluster {
        Some(target) => clusters.get_key_value(target).ok_or_else(|| {
            anyhow::anyhow!(
                "cluster '{}' not found. Available: {}",
                target,
                clusters.keys().cloned().collect::<Vec<_>>().join(", ")
            )
        })?,
        None if clusters.len() > 1 => bail!(
            "lab has {} clusters ({}); pass --cluster=<name>",
            clusters.len(),
            clusters.keys().cloned().collect::<Vec<_>>().join(", ")
        ),
        None => clusters
            .iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("lab has no clusters"))?,
    };

    let waves = value
        .pointer("/content/waves")
        .ok_or_else(|| anyhow::anyhow!("cluster '{name}' has no content.waves"))?;

    serde_json::from_value(waves.clone())
        .with_context(|| format!("reading the wave summary of '{name}'"))
}

fn format_stable(waves: &[Vec<WaveBundle>]) -> String {
    let mut out = String::new();
    for (wave_idx, wave) in waves.iter().enumerate() {
        out.push_str(&format!(
            "=== wave {:03} ({} bundle{}) ===\n",
            wave_idx + 1,
            wave.len(),
            if wave.len() == 1 { "" } else { "s" }
        ));
        for (bundle_idx, bundle) in wave.iter().enumerate() {
            let name = bundle.name.as_str();
            let probe = bundle.has_ready_probe;
            let resources = bundle.resource_count;
            out.push_str(&format!(
                "[{:03}] name={name} hasReadyProbe={probe} resourceCount={resources}\n",
                bundle_idx + 1,
            ));
        }
    }
    golden::normalize_store_paths(&out)
}

fn render_pretty(lab_name: &str, cluster: &str, waves: &[Vec<WaveBundle>]) {
    let total: usize = waves.iter().map(Vec::len).sum();
    println!(
        "{} manifest waves for '{lab_name}' cluster '{cluster}'",
        style("catallaxy").cyan().bold(),
    );
    println!(
        "  {} waves, {} bundles total",
        style(waves.len().to_string()).bold(),
        style(total.to_string()).bold(),
    );
    println!();

    if waves.is_empty() {
        println!("  (no bundles)");
        return;
    }

    for (wave_idx, wave) in waves.iter().enumerate() {
        println!(
            "  {} wave {}/{} ({} bundle{})",
            style("═══").cyan(),
            wave_idx + 1,
            waves.len(),
            wave.len(),
            if wave.len() == 1 { "" } else { "s" },
        );
        for bundle in wave {
            let probe = bundle.has_ready_probe;
            let resources = bundle.resource_count;
            println!(
                "    {} {} {} ({resources} resources)",
                style("•").dim(),
                if probe { "🩺" } else { "  " },
                bundle.name,
            );
        }
    }
}
