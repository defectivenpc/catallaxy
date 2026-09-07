use anyhow::{Context, Result, bail};
use console::style;

use crate::domain::plan::SyncKubeconfigParams;
use crate::plan::StepContext;

pub fn run(sctx: &StepContext<'_>, p: &SyncKubeconfigParams) -> Result<()> {
    let SyncKubeconfigParams {
        target,
        clusters,
        kube_context: kube_context_override,
        from_secret,
    } = p;
    let kube_context_override = kube_context_override.as_deref();

    // Two camps produce a kubeconfig in different places; what this step does
    // with it — write it locally under the context the lab decided — is the
    // same either way, which is why there is one step and not two.
    if let Some(secret) = from_secret {
        return from_store(sctx, clusters, secret);
    }

    let context = kube_context_override
        .map(String::from)
        .map(Ok)
        .unwrap_or_else(|| sctx.lab.kube_context(target).map(String::from))?;
    for cluster_name in clusters {
        println!(
            "{} Syncing kubeconfig for '{cluster_name}'...",
            style(">>>").cyan()
        );
        crate::crossplane::sync_kubeconfig(&context, cluster_name).with_context(|| {
            format!(
                "could not sync the kubeconfig for '{cluster_name}'. Every later \
                 step addresses that cluster through the context this writes, so \
                 continuing would target a stale cluster or none at all"
            )
        })?;
        println!(
            "{} Kubeconfig synced for '{cluster_name}'",
            style(">>>").green(),
        );
    }
    Ok(())
}

/// Take it from a lab secret store, where a state-based apply published it.
///
/// The store is already loaded: the executor opens every store the lab
/// declares before the plan runs, so this is a lookup rather than a fetch.
fn from_store(
    sctx: &StepContext<'_>,
    clusters: &[String],
    secret: &crate::domain::plan::SecretRef,
) -> Result<()> {
    let Some(cache) = sctx.secrets_cache.as_ref() else {
        bail!(
            "the kubeconfig for {} is published to store '{}', and no secret \
             store was loaded for this lab. Declare it under \
             `lab.secrets.stores` so the executor opens it before the plan runs.",
            clusters.join(", "),
            secret.store,
        );
    };

    // `store_of` rather than the store name written twice: a secret's owning
    // store is a fact the lab already holds.
    let value = cache
        .get(&secret.store)
        .and_then(|secrets| secrets.values().find_map(|keys| keys.get(&secret.key)))
        .ok_or_else(|| {
            anyhow::anyhow!(
                "store '{}' holds no '{}'. The apply that creates these \
                 clusters publishes it, so an empty key here means the apply \
                 has not run or its publication names a different address.",
                secret.store,
                secret.key,
            )
        })?;

    for cluster_name in clusters {
        println!(
            "{} Writing kubeconfig for '{cluster_name}' from store '{}'...",
            style(">>>").cyan(),
            secret.store,
        );
        crate::io::kubectl::write_and_merge_kubeconfig(cluster_name, value).with_context(|| {
            format!(
                "could not write the kubeconfig for '{cluster_name}'. Every \
                 later step addresses that cluster through the context this \
                 writes, so continuing would target none at all"
            )
        })?;
        println!(
            "{} Kubeconfig written for '{cluster_name}'",
            style(">>>").green(),
        );
    }
    Ok(())
}
