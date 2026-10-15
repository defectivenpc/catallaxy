use std::path::Path;

pub mod actual;
pub mod reference;
pub use reference::ImageRef;

use anyhow::{Context, Result, bail};
use console::style;

use crate::config::Context as CataContext;
use crate::domain::LabSpec;
use crate::io::nix;

pub async fn warm_to_target_with(
    ctx: &CataContext,
    name: Option<&str>,
    target_registry: &str,
    lab: Option<&LabSpec>,
    lab_pkg: Option<&str>,
) -> Result<()> {
    let images = if let Some(pkg) = lab_pkg {
        load_image_list_from_package(pkg)?
    } else {
        load_image_list(ctx, name)?
    };

    let (upstreams, lab_owned) = match lab {
        Some(lab) => (
            lab.registry_upstreams.clone(),
            lab.lab_owned_registries.clone(),
        ),
        None => {
            let lab = crate::io::nix::get_lab_spec(ctx, &ctx.resolve_lab_name(name)?)?;
            (lab.registry_upstreams, lab.lab_owned_registries)
        }
    };

    println!(
        "{} Warming {} images via {}",
        style("catallaxy").cyan().bold(),
        images.len(),
        style(target_registry).bold(),
    );

    let base = if target_registry.contains("://") {
        target_registry.to_string()
    } else {
        let registry = target_registry.replace("localhost", "127.0.0.1");
        format!("http://{registry}")
    };

    let client = crate::io::http::client(
        reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(360))
            .user_agent("catallaxy-warm/0.1"),
    )?;

    use std::sync::Arc;
    use tokio::sync::{Mutex, Semaphore};
    let tags_cache: Arc<
        Mutex<std::collections::HashMap<String, std::collections::HashSet<String>>>,
    > = Arc::new(Mutex::new(std::collections::HashMap::new()));

    let concurrency = crate::io::fs::env_var("CATA_WARM_CONCURRENCY")
        .and_then(|s| s.parse::<usize>().ok())
        .filter(|n| *n > 0)
        .unwrap_or(8);
    let sem = Arc::new(Semaphore::new(concurrency));

    let base = Arc::new(base);
    let client = Arc::new(client);
    let upstreams = Arc::new(upstreams);
    let lab_owned = Arc::new(lab_owned);

    let mut tasks = tokio::task::JoinSet::new();
    for image in images.clone() {
        let sem = sem.clone();
        let tags_cache = tags_cache.clone();
        let base = base.clone();
        let client = client.clone();
        let upstreams = upstreams.clone();
        let lab_owned = lab_owned.clone();
        tasks.spawn(async move {
            let _permit = sem.acquire_owned().await.expect("semaphore closed");
            warm_one_image(&image, &base, &client, &upstreams, &lab_owned, &tags_cache).await
        });
    }

    report_warm_results(&mut tasks, images.len()).await
}

async fn warm_one_image(
    image: &str,
    base: &str,
    client: &reqwest::Client,
    upstreams: &[String],
    lab_owned: &[String],
    tags_cache: &tokio::sync::Mutex<
        std::collections::HashMap<String, std::collections::HashSet<String>>,
    >,
) -> WarmOutcome {
    let r = match plan_warm(image, upstreams, lab_owned) {
        WarmRoute::LabPublished => {
            println!(
                "{} {image}... {} (lab-published)",
                style(">>>").cyan(),
                style("skip").dim()
            );
            return WarmOutcome::LabPublished;
        }
        WarmRoute::NoUpstream(registry) => {
            println!(
                "{} {image}... {} (no upstream for '{registry}')",
                style(">>>").cyan(),
                style("skip").dim(),
            );
            return WarmOutcome::NotMirrored(image.to_string());
        }
        WarmRoute::Fetch(r) => r,
    };

    let cache_key = r.tag.clone().unwrap_or_else(|| r.reference());

    let cached = {
        let cache = tags_cache.lock().await;
        cache
            .get(&r.api_repository())
            .map(|tags| tags.contains(&cache_key))
    };
    let cached = match cached {
        Some(hit) => hit,
        None => {
            let mut tags = std::collections::HashSet::new();
            if let Ok(resp) = client.get(tags_url(base, &r.api_repository())).send().await
                && resp.status().is_success()
                && let Ok(body) = resp.json::<serde_json::Value>().await
            {
                tags = tags_from_body(&body);
            }
            let hit = tags.contains(&cache_key);
            tags_cache.lock().await.insert(r.api_repository(), tags);
            hit
        }
    };

    if cached {
        println!(
            "{} {image}... {}",
            style(">>>").cyan(),
            style("cached").dim()
        );
        return WarmOutcome::Ok;
    }

    let sync_url = sync_url(base, &r);
    let accept = "application/vnd.oci.image.index.v1+json,\
                  application/vnd.oci.image.manifest.v1+json,\
                  application/vnd.docker.distribution.manifest.list.v2+json,\
                  application/vnd.docker.distribution.manifest.v2+json";

    let resp = client
        .get(&sync_url)
        .header(reqwest::header::ACCEPT, accept)
        .send()
        .await;

    match resp {
        Ok(resp) if resp.status().is_success() => {
            tags_cache.lock().await.remove(&r.api_repository());
            println!(
                "{} {image}... {}",
                style(">>>").cyan(),
                style("warmed").green()
            );
            WarmOutcome::Ok
        }
        Ok(resp) => {
            println!(
                "{} {image}... {} ({})",
                style(">>>").cyan(),
                style("failed").red(),
                style(format!("HTTP {}", resp.status().as_u16())).dim()
            );
            WarmOutcome::Failed
        }
        Err(e) => {
            println!(
                "{} {image}... {} ({})",
                style(">>>").cyan(),
                style("failed").red(),
                style(format!("{e}")).dim()
            );
            WarmOutcome::Failed
        }
    }
}

async fn report_warm_results(
    tasks: &mut tokio::task::JoinSet<WarmOutcome>,
    total: usize,
) -> Result<()> {
    let mut failed = 0usize;
    let mut skipped = 0usize;
    let mut not_mirrored: Vec<String> = Vec::new();
    while let Some(res) = tasks.join_next().await {
        match res {
            Ok(WarmOutcome::Ok) => {}
            Ok(WarmOutcome::LabPublished) => skipped += 1,
            Ok(WarmOutcome::NotMirrored(image)) => {
                skipped += 1;
                not_mirrored.push(image);
            }
            Ok(WarmOutcome::Failed) => failed += 1,
            Err(join_err) => {
                failed += 1;
                eprintln!(
                    "{} warm task panicked: {}",
                    style(">>>").red(),
                    style(format!("{join_err}")).dim()
                );
            }
        }
    }

    println!();
    if !not_mirrored.is_empty() {
        not_mirrored.sort();
        println!(
            "{} {} image(s) are not in the lab's cache because no upstream is \
             configured for their registry:",
            style("Warning:").yellow(),
            not_mirrored.len(),
        );
        for image in &not_mirrored {
            println!("      {image}");
        }
        println!(
            "      The cluster pulls these from the public internet when it \
             deploys. If that registry is unreachable, the workload will sit in \
             ImagePullBackOff and surface as a readyProbe timeout rather than as \
             a pull failure. Add the registry to `lab.registry.upstreams` to \
             mirror it."
        );
    }

    let processed = total - failed - skipped;
    if failed == 0 {
        println!(
            "{} Cache: {processed} ready, {skipped} skipped",
            style(">>>").green(),
        );
    } else {
        println!(
            "{} Cache: {processed} ready, {skipped} skipped, {failed} failed (continuing; \
             affected deployments will retry)",
            style(">>>").yellow(),
        );
    }
    Ok(())
}

pub fn load_image_list_from_package(lab_package: &str) -> Result<Vec<String>> {
    let images_path = Path::new(lab_package).join("images.txt");
    if !images_path.exists() {
        bail!("No images.txt found in lab package. Rebuild with latest catallaxy.");
    }
    let content = crate::io::fs::read_to_string(&images_path)
        .with_context(|| format!("reading {}", images_path.display()))?;
    Ok(content
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect())
}

pub fn load_image_list(ctx: &CataContext, name: Option<&str>) -> Result<Vec<String>> {
    let lab_name = ctx.resolve_lab_name(name)?;
    let lab_package = nix::build_lab_package(ctx, &lab_name)?;
    let images_path = Path::new(&lab_package).join("images.txt");

    if !images_path.exists() {
        bail!("No images.txt found in lab package. Rebuild with latest catallaxy.");
    }

    let content = crate::io::fs::read_to_string(&images_path)
        .with_context(|| format!("reading {}", images_path.display()))?;

    let images: Vec<String> = content
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();

    Ok(images)
}

pub enum WarmOutcome {
    Ok,
    /// The lab publishes this image itself, so there is nothing to mirror.
    LabPublished,
    /// No upstream is configured for this image's registry, so the cluster
    /// pulls it from the public internet at deploy time rather than from the
    /// lab's cache. Not a failure, but not the same as cached either.
    NotMirrored(String),
    Failed,
}

#[derive(Debug, PartialEq, Eq)]
pub enum WarmRoute {
    LabPublished,
    NoUpstream(String),
    Fetch(ImageRef),
}

pub fn plan_warm(image: &str, upstreams: &[String], lab_owned: &[String]) -> WarmRoute {
    let r = ImageRef::parse(image);
    if lab_owned.iter().any(|h| h == &r.registry) {
        WarmRoute::LabPublished
    } else if !upstreams.iter().any(|h| h == &r.registry) {
        WarmRoute::NoUpstream(r.registry)
    } else {
        WarmRoute::Fetch(r)
    }
}

pub fn tags_from_body(body: &serde_json::Value) -> std::collections::HashSet<String> {
    body.get("tags")
        .and_then(|t| t.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str())
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

pub fn tags_url(base: &str, repo: &str) -> String {
    format!("{base}/v2/{repo}/tags/list")
}

pub fn sync_url(base: &str, r: &ImageRef) -> String {
    format!(
        "{base}/v2/{}/manifests/{}?ns={}",
        r.api_repository(),
        r.reference(),
        r.registry,
    )
}

#[cfg(test)]
mod warm_tests {
    use super::*;

    fn hosts(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn an_image_from_a_lab_registry_is_never_pulled_through_the_mirror() {
        assert_eq!(
            plan_warm(
                "registry.lab.local/team/app:v1",
                &hosts(&["docker.io"]),
                &hosts(&["registry.lab.local"]),
            ),
            WarmRoute::LabPublished
        );
    }

    #[test]
    fn lab_ownership_wins_over_a_registry_that_is_also_an_upstream() {
        assert_eq!(
            plan_warm(
                "registry.lab.local/team/app:v1",
                &hosts(&["registry.lab.local"]),
                &hosts(&["registry.lab.local"]),
            ),
            WarmRoute::LabPublished
        );
    }

    #[test]
    fn an_image_with_no_configured_upstream_names_the_registry_it_wanted() {
        assert_eq!(
            plan_warm("quay.io/team/app:v1", &hosts(&["docker.io"]), &[]),
            WarmRoute::NoUpstream("quay.io".to_string())
        );
    }

    #[test]
    fn an_upstream_image_is_routed_to_a_fetch_carrying_its_parsed_reference() {
        let WarmRoute::Fetch(r) =
            plan_warm("docker.io/library/nginx:1.25", &hosts(&["docker.io"]), &[])
        else {
            panic!("expected a fetch");
        };
        assert_eq!(r.registry, "docker.io");
        assert_eq!(r.reference(), "1.25");
    }

    #[test]
    fn a_tags_list_becomes_a_set_of_tag_names() {
        let body = serde_json::json!({ "name": "library/nginx", "tags": ["1.25", "latest"] });
        let tags = tags_from_body(&body);
        assert!(tags.contains("1.25"));
        assert!(tags.contains("latest"));
        assert_eq!(tags.len(), 2);
    }

    #[test]
    fn a_repository_with_no_tags_yields_an_empty_set_rather_than_failing() {
        assert!(tags_from_body(&serde_json::json!({ "tags": null })).is_empty());
        assert!(tags_from_body(&serde_json::json!({})).is_empty());
    }

    #[test]
    fn the_sync_url_asks_the_mirror_for_the_upstream_namespace() {
        let r = ImageRef::parse("docker.io/library/nginx:1.25");
        assert_eq!(
            sync_url("http://localhost:5000", &r),
            "http://localhost:5000/v2/library/nginx/manifests/1.25?ns=docker.io"
        );
        assert_eq!(
            tags_url("http://localhost:5000", &r.api_repository()),
            "http://localhost:5000/v2/library/nginx/tags/list"
        );
    }
}
