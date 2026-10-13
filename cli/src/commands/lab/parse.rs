//! Does `cata` understand this document?
//!
//! The lab document is what every command acts on, and until this existed
//! nothing read one through the parser except the command that was about to
//! use it. `cliConfig-<lab>` diffs the emitted document byte for byte, which
//! catches a document that *changed* and not one the CLI cannot parse: a
//! field Nix renamed, a variant it grew, a number where a string was. Both
//! sides agreeing is the half of the tightness law that a diff cannot state.
//!
//! So this parses and says what it found, and `cluster-documents` runs it
//! over every committed document in the tree.

use std::path::Path;

use anyhow::{Context, Result};
use console::style;

use crate::config::Context as CataContext;
use crate::domain::LabSpec;

/// Parse a lab document, from a file or by evaluating the lab, and report
/// what the claim of each cluster says.
pub fn run(ctx: &CataContext, name: Option<&str>, from_file: Option<&Path>) -> Result<()> {
    let lab = match from_file {
        Some(path) => read(path)?,
        None => {
            let lab_name = ctx.resolve_lab_name(name)?;
            crate::io::nix::get_lab_spec(ctx, &lab_name)?
        }
    };

    let source = from_file.map_or_else(|| lab.lab_name.clone(), |p| p.display().to_string());
    println!(
        "{} {} parses: {} cluster(s)",
        style("✓").green(),
        source,
        lab.clusters.len()
    );

    for (name, cluster) in &lab.clusters {
        let claim = &cluster.claim;
        let variant = cluster.provisioning.config.kind().tag();
        let bundles: usize = cluster.content.waves.iter().map(Vec::len).sum();
        let version = claim.kubernetes.version.as_str();
        let context = claim.context.as_str();
        println!(
            "    {} {} [{variant}] kubernetes {version}, context {context}, {bundles} bundle(s)",
            style("-").dim(),
            style(name).cyan(),
        );
    }

    Ok(())
}

fn read(path: &Path) -> Result<LabSpec> {
    let raw = crate::io::fs::read_to_string(path)
        .with_context(|| format!("reading the lab document {}", path.display()))?;
    let value =
        serde_json::from_str(&raw).with_context(|| format!("{} is not JSON", path.display()))?;
    LabSpec::from_value(value).with_context(|| {
        format!(
            "{} is JSON but not a lab document this cata understands",
            path.display()
        )
    })
}
