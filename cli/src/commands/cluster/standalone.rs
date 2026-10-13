//! A cluster stood up from its own document.
//!
//! The test this exists to answer: can `cata` stand up a cluster given
//! nothing but the cluster's own document? Everything else in the CLI
//! resolves a cluster *through* a lab — `load_cluster_spec` evaluates the lab
//! and digs the cluster out, `ensure_lab_services` scans every lab on the
//! flake — so a field that leaked back to the lab was invisible. Here it is a
//! parse failure naming the field.
//!
//! What it deliberately does not do is a plan. A lab's plan orders host
//! services, cross-cluster secret copies and one cluster waiting on another;
//! a cluster on its own has none of those, and the honest sequence is the
//! short one: bring the claim into existence, then converge the content onto
//! it. A cluster that needs more than that is a cluster something else has to
//! close, which is what a lab is for.

use std::path::Path;

use anyhow::{Context, Result};
use console::style;

use crate::config::Context as CataContext;
use crate::domain::{ClusterSpec, SecretsSpec};
use crate::io;

/// Read one cluster document.
pub fn read(path: &Path) -> Result<ClusterSpec> {
    let raw = io::fs::read_to_string(path)
        .with_context(|| format!("reading the cluster document {}", path.display()))?;
    let value =
        serde_json::from_str(&raw).with_context(|| format!("{} is not JSON", path.display()))?;
    ClusterSpec::from_value(value).with_context(|| {
        format!(
            "{} is JSON but not a cluster document this cata understands",
            path.display()
        )
    })
}

/// Read one cluster document and say what it declares.
///
/// The counterpart of `lab parse`, for the artifact a cluster is on its own.
/// `cluster-artifact-<lab>-<cluster>` runs it over every one in the tree,
/// which is the sandbox-safe half of the question `up` answers for real:
/// everything a cluster needs is in its own document, or this fails naming
/// the field that is not.
pub fn parse(path: &Path) -> Result<()> {
    let spec = read(path)?;
    let claim = &spec.claim;
    let variant = spec.provisioning.config.kind().tag();
    let bundles: usize = spec.content.waves.iter().map(Vec::len).sum();
    let strategy = spec.delivery.strategy.tag();

    println!(
        "{} {} parses on its own",
        style("✓").green(),
        style(&claim.name).cyan()
    );
    println!("    claim        {} [{variant}]", claim.instance_name);
    println!(
        "    kubernetes   {} ({} control plane(s), {} worker(s))",
        claim.kubernetes.version, claim.kubernetes.control_planes, claim.kubernetes.workers
    );
    println!(
        "    content      {bundles} bundle(s) in {}",
        spec.content.tree
    );
    println!("    delivery     {strategy}");

    Ok(())
}

/// Provision the claim and apply the content, from the document alone.
pub fn up(ctx: &CataContext, path: &Path, dry_run: bool) -> Result<()> {
    io::process::check_required_tools()?;

    let spec = read(path)?;
    let name = spec.claim.name.clone();

    println!(
        "{} Standing up '{}' from {}",
        style("catallaxy").cyan().bold(),
        style(&name).green(),
        path.display()
    );

    crate::provision::provision_cluster_with_registry(ctx, &name, &spec, None, None)?;

    apply(ctx, &spec, dry_run)
}

/// Converge the content onto the claim.
fn apply(ctx: &CataContext, spec: &ClusterSpec, dry_run: bool) -> Result<()> {
    let tree = Path::new(&spec.content.tree);
    let wait = &spec.delivery.wait_timeout;
    let seconds = io::kubectl::parse_timeout(wait)
        .with_context(|| format!("delivery.waitTimeout is '{wait}', which is not a duration"))?
        .as_secs();

    println!(
        "{} Applying {} wave(s) from {}",
        style(">>>").cyan(),
        spec.content.waves.len(),
        tree.display()
    );

    io::ssa::apply_manifest_root(
        ctx,
        io::ssa::ApplyManifests {
            kube_context: &spec.claim.context,
            manifest_root: tree,
            field_manager: "cata",
            wait_timeout_seconds: seconds,
            dry_run,
            cluster: Some(spec),

            lab_name: &spec.claim.instance_name,
            secrets_spec: &SecretsSpec::default(),
            secrets_cache: None,
        },
    )
}
