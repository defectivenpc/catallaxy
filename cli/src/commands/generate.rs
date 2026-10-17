use std::collections::BTreeMap;
use std::io::{self, Read};
use std::path::Path;

use anyhow::{Context, Result};
use clap::Args;
use console::style;
use serde::Deserialize;

use crate::config::Context as CataContext;

#[derive(Args)]
pub struct GenerateArgs {
    #[arg(
        default_value = "-",
        value_name = "PATH",
        help = "Generator config JSON. '-' reads stdin"
    )]
    config: String,

    #[arg(
        short,
        long,
        value_name = "DIR",
        help = "Where to write the types, overriding the config's outputDir"
    )]
    output: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GenerateConfig {
    output_dir: String,

    #[serde(default)]
    crds: BTreeMap<String, String>,
}

pub fn run(_ctx: &CataContext, args: GenerateArgs) -> Result<()> {
    let json = if args.config == "-" {
        let mut buffer = String::new();
        io::stdin()
            .read_to_string(&mut buffer)
            .context("Failed to read from stdin")?;
        buffer
    } else {
        crate::io::fs::read_to_string(&args.config)
            .with_context(|| format!("Failed to read config file: {}", args.config))?
    };

    let mut config: GenerateConfig =
        serde_json::from_str(&json).context("Failed to parse JSON config")?;

    if let Some(output) = args.output {
        config.output_dir = output;
    }

    generate(config)
}

/// Files CRD schemas by the API group they belong to rather than by the source
/// they were read from, because the group is what a resource is resolved under.
/// One source can define several groups — crossplane defines three — and one
/// group can be split across sources.
///
/// One source per group, not merely one per kind: the group's schema is
/// written into that source's own directory, so two sources contributing to
/// one group would be two places claiming one file.
///
/// Two sources defining the same `group/Kind` is refused. Merging them would
/// make the emitted schema depend on read order, which is the kind of thing
/// that holds until someone reorders a config.
type Group = (String, serde_json::Map<String, serde_json::Value>);

fn group_schemas_by_api_group(
    per_source: Vec<(String, serde_json::Map<String, serde_json::Value>)>,
) -> Result<BTreeMap<String, Group>> {
    let mut by_group: BTreeMap<String, Group> = BTreeMap::new();
    let mut defined_by: BTreeMap<(String, String), String> = BTreeMap::new();

    for (source, kinds) in per_source {
        for (kind, entry) in kinds {
            let group = entry
                .get("apiVersion")
                .and_then(serde_json::Value::as_str)
                .and_then(|av| av.split('/').next())
                .context("a CRD schema with no apiVersion group")?
                .to_string();

            let coordinate = (group.clone(), kind.clone());

            if let Some(first) = defined_by.get(&coordinate) {
                anyhow::bail!(
                    "{group}/{kind} is defined by both '{first}' and '{source}'.\n\
                     Two sources claiming one kind would make the generated schema \
                     depend on which was read last. Exclude it from one of them."
                );
            }

            defined_by.insert(coordinate, source.clone());

            match by_group.get_mut(&group) {
                Some((owner, group_kinds)) if *owner == source => {
                    group_kinds.insert(kind, entry);
                }
                Some((owner, _)) => anyhow::bail!(
                    "API group '{group}' is defined by both '{owner}' and '{source}'.\n\
                     Its schema is written beside the floe that installs it, so two \
                     sources contributing to one group would be two floes claiming \
                     one file. Give the group one source."
                ),
                None => {
                    let mut m = serde_json::Map::new();
                    m.insert(kind, entry);
                    by_group.insert(group, (source.clone(), m));
                }
            }
        }
    }

    Ok(by_group)
}

fn generate(config: GenerateConfig) -> Result<()> {
    let output_dir = Path::new(&config.output_dir);

    let mut per_source = Vec::new();

    for (name, crd_path) in &config.crds {
        eprintln!("{} Reading CRDs from {}", style(">>>").cyan(), name);

        let crd_content = crate::io::fs::read_to_string(crd_path)
            .with_context(|| format!("Failed to read CRD file: {crd_path}"))?;

        let schemas = crate::codegen::crd::crd_schemas_from_yaml(&crd_content)
            .with_context(|| format!("Failed to parse CRD: {crd_path}"))?;

        eprintln!("    Found {} CRD types", schemas.len());
        per_source.push((name.clone(), schemas));
    }

    let by_group = group_schemas_by_api_group(per_source)?;

    // `<source>/crds/<group>.json`, because the schema lives beside the floe
    // that installs the CRDs. The caller copies each source's directory into
    // that floe's, so the layout here is the layout there.
    for (group, (source, kinds)) in &by_group {
        let dir = output_dir.join(source).join("crds");
        crate::io::fs::create_dir_all(&dir).with_context(|| format!("Failed to create {dir:?}"))?;

        let file_path = dir.join(format!("{group}.json"));
        let json = serde_json::to_string_pretty(kinds).context("serialising a CRD group")?;
        crate::io::fs::write(&file_path, format!("{json}\n").as_str())
            .with_context(|| format!("Failed to write {file_path:?}"))?;

        eprintln!(
            "    {} {} kinds -> {file_path:?}",
            style(group).green(),
            kinds.len()
        );
    }

    eprintln!(
        "\n{} Done! Generated types in {:?}",
        style(">>>").green(),
        output_dir
    );

    Ok(())
}

/// `cata-build document <out>` — the lab document's shape, as a `floes` type.
///
/// Emitted from `schemars` over `LabSpec`, so adding a field to the struct the
/// parser uses is what changes the type Nix checks against.
pub fn document(out: &str) -> Result<()> {
    let nix = crate::codegen::document::lab_document()?;
    crate::io::fs::write(out, &nix).with_context(|| format!("writing {out}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_config() {
        let json = r#"{
            "outputDir": "/tmp/generated",
            "k8sVersions": {
                "1.31": "/nix/store/abc/swagger.json"
            },
            "crds": {
                "cert-manager": "/nix/store/xyz/crds.yaml"
            }
        }"#;

        let config: GenerateConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.output_dir, "/tmp/generated");
        assert_eq!(config.crds.len(), 1);
    }

    /// One kind's entry, as `crd_schemas_from_yaml` yields it.
    fn crd(group: &str, kind: &str) -> (String, serde_json::Value) {
        (
            kind.to_string(),
            serde_json::json!({ "apiVersion": format!("{group}/v1"), "schema": {} }),
        )
    }

    fn source(
        name: &str,
        kinds: Vec<(String, serde_json::Value)>,
    ) -> (String, serde_json::Map<String, serde_json::Value>) {
        (name.to_string(), kinds.into_iter().collect())
    }

    #[test]
    fn one_source_defining_several_groups_lands_in_a_file_each() {
        let grouped = group_schemas_by_api_group(vec![source(
            "cert-manager",
            vec![
                crd("cert-manager.io", "Certificate"),
                crd("acme.cert-manager.io", "Challenge"),
            ],
        )])
        .unwrap();

        assert_eq!(
            grouped.keys().collect::<Vec<_>>(),
            vec!["acme.cert-manager.io", "cert-manager.io"]
        );
        assert_eq!(grouped["cert-manager.io"].0, "cert-manager");
    }

    #[test]
    fn one_group_split_across_sources_is_refused() {
        let err = group_schemas_by_api_group(vec![
            source("a", vec![crd("example.io", "Alpha")]),
            source("b", vec![crd("example.io", "Beta")]),
        ])
        .unwrap_err()
        .to_string();

        assert!(err.contains("example.io"), "{err}");
        assert!(err.contains("'a'") && err.contains("'b'"), "{err}");
    }

    #[test]
    fn two_sources_claiming_one_kind_is_refused() {
        let err = group_schemas_by_api_group(vec![
            source("first", vec![crd("example.io", "Thing")]),
            source("second", vec![crd("example.io", "Thing")]),
        ])
        .unwrap_err()
        .to_string();

        assert!(err.contains("example.io/Thing"), "{err}");
        assert!(err.contains("'first'") && err.contains("'second'"), "{err}");
    }
}
