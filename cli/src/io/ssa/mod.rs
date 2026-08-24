use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::thread::sleep;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use console::style;

use crate::apply::{ProjectionSource, inject_projections_with};
use crate::config::Context as CataContext;
use crate::domain::SecretsCache;
use crate::domain::cluster::ProjectionConfig;
use crate::domain::{ClusterSpec, SecretsSpec};
use crate::io;

mod probe;
mod prune;
mod readiness;
mod tree;

pub use probe::ReadyProbe;
use probe::run_ready_probe;

pub use prune::relinquish_field_manager;
pub use tree::{Wave, WaveBundle, WaveMeta, read_wave_meta};

use prune::prune_undeclared;
use readiness::wait_workloads_ready;

fn apply_wave_bundles(
    ctx: &CataContext,
    opts: &ApplyManifests<'_>,
    wave: &Wave,
    manifest_root: &Path,
    timeout_str: &str,
) -> Result<()> {
    let &ApplyManifests {
        kube_context,
        field_manager,
        dry_run,
        ..
    } = opts;
    for bundle in &wave.bundles {
        if bundle.key.starts_with("projection/") {
            continue;
        }
        let bundle_dir = manifest_root.join(&bundle.dir);
        if !bundle_dir.exists() {
            if bundle.has_content {
                println!(
                    "{} bundle '{}' declares content but {} is missing, nothing applied",
                    style(">>>").yellow(),
                    bundle.key,
                    bundle_dir.display(),
                );
            }
            continue;
        }
        apply_bundle_with_retry(
            kube_context,
            field_manager,
            &bundle.key,
            &bundle_dir,
            dry_run,
        )?;

        wait_bundle_crds(
            ctx,
            kube_context,
            &bundle.key,
            &bundle_dir,
            timeout_str,
            dry_run,
        )?;
    }

    Ok(())
}

fn await_wave_bundles(
    ctx: &CataContext,
    opts: &ApplyManifests<'_>,
    wave: &Wave,
    manifest_root: &Path,
    timeout_str: &str,
) -> Result<()> {
    let &ApplyManifests {
        kube_context,
        dry_run,
        ..
    } = opts;
    for bundle in &wave.bundles {
        if !bundle.has_content {
            continue;
        }
        // Workloads first, then the probe, and never one instead of the
        // other. A probe says "this bundle's own thing is working" -- an
        // Issuer answers, a CR reports Ready -- which is a narrower question
        // than "every Deployment I shipped is Available". Treating the probe
        // as a replacement let the next wave start against a bundle whose
        // pods were still coming up, which is how a webhook-owning bundle
        // like cert-manager races the resources that need its webhook.
        //
        // A bundle with no workloads makes the wait a no-op, so this costs
        // nothing where the probe was genuinely the only signal available.
        if !dry_run {
            wait_workloads_ready(kube_context, &manifest_root.join(&bundle.dir), timeout_str)?;
        }
        if let Some(probe) = &bundle.ready_probe {
            run_ready_probe(ctx, kube_context, &bundle.key, probe, timeout_str, dry_run)?;
        }
    }
    Ok(())
}

/// How long to keep re-applying a bundle that will not take yet.
///
/// A bundle can contain both an admission webhook and the objects that webhook
/// validates: kube-prometheus-stack ships its operator, the
/// `MutatingWebhookConfiguration` pointing at it, and the PrometheusRules it
/// checks, all in one Helm release. `kubectl apply` sends them together, so the
/// rules are rejected until the operator has an endpoint, and retrying is the
/// only thing that can succeed.
///
/// This used to be four attempts, which with the backoff below is eighteen
/// seconds of waiting. That is shorter than a cold image pull, so whether it
/// worked came down to how much else had already been installed: prometheus
/// passed only because an unrelated edge happened to place it late. Deleting
/// that edge, correctly, made it fail. A deadline says what the retry is
/// actually for, and does not depend on where in the plan the bundle lands.
const BUNDLE_APPLY_DEADLINE: Duration = Duration::from_secs(180);
const PHASE_APPLY_BACKOFF: Duration = Duration::from_secs(6);

pub struct ApplyManifests<'a> {
    pub kube_context: &'a str,
    pub manifest_root: &'a Path,
    pub field_manager: &'a str,
    pub wait_timeout_seconds: u64,
    pub dry_run: bool,
    pub cluster: Option<&'a ClusterSpec>,
    pub lab_name: &'a str,
    pub secrets_spec: &'a SecretsSpec,
    pub secrets_cache: Option<&'a SecretsCache>,
}

/// Server-side apply every manifest under `manifest_root`, in phase order,
/// then wait for the workloads it created.
///
/// # Errors
///
/// If the kube context is empty, if `manifest_root` does not exist, if a phase
/// still fails after its retries, or if a workload never becomes ready within
/// `wait_timeout_seconds`. A missing manifest root is an error rather than an
/// empty apply, because it means the lab package was not built.
pub fn apply_manifest_root(ctx: &CataContext, opts: ApplyManifests<'_>) -> Result<()> {
    let ApplyManifests {
        manifest_root,
        wait_timeout_seconds,
        ..
    } = opts;
    crate::io::kube_context::require_named(opts.kube_context)?;

    if !manifest_root.exists() {
        bail!(
            "manifest root not found at {}. Rebuild the lab package.",
            manifest_root.display(),
        );
    }

    let timeout_str = format!("{wait_timeout_seconds}s");

    let wave_meta_path = manifest_root.join(".wave-meta");
    if !wave_meta_path.exists() {
        bail!(
            "no .wave-meta at {}: the manifest tree was rendered by an \
             older catallaxy. Re-render the lab.",
            manifest_root.display()
        );
    }
    apply_wave_ordered(ctx, &opts, &wave_meta_path, &timeout_str)
}

fn apply_wave_ordered(
    ctx: &CataContext,
    opts: &ApplyManifests<'_>,
    wave_meta_path: &Path,
    timeout_str: &str,
) -> Result<()> {
    let &ApplyManifests {
        kube_context,
        manifest_root,
        field_manager,
        dry_run,
        cluster,
        lab_name,
        secrets_spec,
        secrets_cache,
        ..
    } = opts;
    let raw = fs::read_to_string(wave_meta_path)
        .with_context(|| format!("reading .wave-meta at {}", wave_meta_path.display()))?;
    let meta: WaveMeta = serde_json::from_str(&raw)
        .with_context(|| format!("parsing .wave-meta at {}", wave_meta_path.display()))?;

    let projections: BTreeMap<String, ProjectionConfig> =
        cluster.map(|c| c.projections.clone()).unwrap_or_default();

    let projections_for_wave = |wave: &Wave| -> Vec<(String, ProjectionConfig)> {
        wave.bundles
            .iter()
            .filter_map(|b| b.key.strip_prefix("projection/"))
            .filter_map(|name| projections.get(name).map(|p| (name.to_string(), p.clone())))
            .collect()
    };

    println!(
        "{} Applying {wave_count} wave(s) via kubectl SSA on '{kube_context}' \
         (field-manager={field_manager})",
        style(">>>").cyan(),
        wave_count = meta.waves.len(),
    );

    for wave in &meta.waves {
        let bundle_count = wave.bundles.len();
        println!(
            "\n{} Wave {:03} ({bundle_count} bundle{})",
            style(">>>").cyan(),
            wave.index + 1,
            if bundle_count == 1 { "" } else { "s" },
        );

        let wave_projections = projections_for_wave(wave);
        if !wave_projections.is_empty() {
            inject_projections_ssa(
                ctx,
                kube_context,
                &ProjectionSource {
                    lab_name,
                    secrets: secrets_spec,
                    pre_cache: secrets_cache.map(|v| &**v),
                },
                &wave_projections,
                field_manager,
                dry_run,
            )?;
        }

        apply_wave_bundles(ctx, opts, wave, manifest_root, timeout_str)?;
        await_wave_bundles(ctx, opts, wave, manifest_root, timeout_str)?;
    }

    println!(
        "\n{} SSA wave apply complete on '{kube_context}'",
        style(">>>").green(),
    );

    prune_undeclared(opts, &meta, manifest_root)
}

fn apply_bundle_with_retry(
    kube_context: &str,
    field_manager: &str,
    bundle_key: &str,
    bundle_dir: &Path,
    dry_run: bool,
) -> Result<()> {
    if dry_run {
        println!(
            "{} Would kubectl apply bundle '{bundle_key}' from {}",
            style(">>>").yellow(),
            bundle_dir.display(),
        );
        return Ok(());
    }
    let started = Instant::now();
    let mut attempt = 0u32;
    loop {
        attempt += 1;
        let status = crate::io::kubectl::command()
            .args([
                "--context",
                kube_context,
                "apply",
                "--server-side",
                "--force-conflicts",
                "--field-manager",
                field_manager,
                "-f",
            ])
            .arg(bundle_dir)
            .arg("--recursive")
            .status()
            .context("running kubectl apply --server-side for bundle")?;
        if status.success() {
            println!("{} Applied bundle '{bundle_key}'", style(">>>").green(),);
            return Ok(());
        }
        if started.elapsed() + PHASE_APPLY_BACKOFF >= BUNDLE_APPLY_DEADLINE {
            bail!(
                "kubectl apply of bundle '{bundle_key}' failed after {attempt} attempts over \
                 {elapsed}s: kubectl apply exited with {status}",
                elapsed = started.elapsed().as_secs(),
            );
        }
        println!(
            "{} kubectl apply of bundle '{bundle_key}' failed (attempt {attempt}, {elapsed}s of \
             {deadline}s); sleeping {backoff}s and retrying.",
            style(">>>").yellow(),
            elapsed = started.elapsed().as_secs(),
            deadline = BUNDLE_APPLY_DEADLINE.as_secs(),
            backoff = PHASE_APPLY_BACKOFF.as_secs(),
        );
        sleep(PHASE_APPLY_BACKOFF);
    }
}

fn wait_bundle_crds(
    _ctx: &CataContext,
    kube_context: &str,
    bundle_key: &str,
    bundle_dir: &Path,
    timeout: &str,
    dry_run: bool,
) -> Result<()> {
    let marker = bundle_dir.join(".crd-wait");
    if !marker.exists() {
        return Ok(());
    }
    let content =
        fs::read_to_string(&marker).with_context(|| format!("reading {}", marker.display()))?;
    let crds: Vec<&str> = content
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .collect();
    if crds.is_empty() {
        return Ok(());
    }
    if dry_run {
        println!(
            "{} Would wait for {} CRD(s) from '{bundle_key}' to be Established",
            style(">>>").yellow(),
            crds.len(),
        );
        return Ok(());
    }
    println!(
        "{} Waiting for {} CRD(s) from '{bundle_key}' to be Established",
        style(">>>").cyan(),
        crds.len(),
    );
    for crd in crds {
        io::kubectl::wait_crd_established(kube_context, crd, timeout)?;
    }
    Ok(())
}

fn inject_projections_ssa(
    ctx: &CataContext,
    kube_context: &str,
    source: &ProjectionSource<'_>,
    projections: &[(String, ProjectionConfig)],
    field_manager: &str,
    dry_run: bool,
) -> Result<()> {
    inject_projections_with(ctx, source, projections, |secret_dir, secret_name| {
        if dry_run {
            println!(
                "{} Would kubectl apply --context {kube_context} --server-side \
                     --force-conflicts --field-manager={field_manager} -f {} --recursive",
                style(">>>").yellow(),
                secret_dir.display(),
            );
            return Ok(());
        }
        println!(
            "{} Applying projection Secret '{secret_name}' via SSA",
            style(">>>").cyan(),
        );
        let status = crate::io::kubectl::command()
            .args([
                "--context",
                kube_context,
                "apply",
                "--server-side",
                "--force-conflicts",
                "--field-manager",
                field_manager,
                "-f",
            ])
            .arg(secret_dir)
            .arg("--recursive")
            .status()
            .context("running kubectl apply --server-side for projection Secret")?;
        if !status.success() {
            bail!("kubectl apply of projection Secret '{secret_name}' exited with {status}",);
        }
        Ok(())
    })
}
