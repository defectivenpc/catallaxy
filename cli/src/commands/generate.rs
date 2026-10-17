use std::collections::BTreeMap;
use std::io::{self, Read};
use std::path::Path;

use anyhow::{Context, Result};
use clap::Args;
use console::style;
use serde::Deserialize;

use crate::codegen::types::K8sResourceType;
use crate::codegen::{
    EmitterConfig, GeneratorOptions, convert_openapi_to_types, emit_crd_types, emit_k8s_types,
    parse_crds_from_yaml, parse_openapi_spec,
};
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
    k8s_versions: BTreeMap<String, String>,

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

/// Files CRD types by the API group they belong to rather than by the source
/// they were read from, because the group is what a resource is resolved under.
/// One source can define several groups — crossplane defines three — and one
/// group can be split across sources.
///
/// Two sources defining the same `group/Kind` is refused. Merging them would
/// make the emitted type depend on read order, which is the kind of thing that
/// holds until someone reorders a config.
///
/// ```ignore
/// let grouped = group_by_api_group(vec![
///     ("cert-manager".into(), vec![certificate, challenge]),
/// ])?;
/// // -> { "cert-manager.io": [certificate], "acme.cert-manager.io": [challenge] }
/// ```
/// Every API group, the source that defines it, and its kinds.
///
/// One source per group, not merely one per kind: the group's types are written
/// into that source's own directory, so two sources contributing to one group
/// would be two places claiming one file. A group has exactly one home.
fn group_by_api_group(
    per_source: Vec<(String, Vec<K8sResourceType>)>,
) -> Result<BTreeMap<String, (String, Vec<K8sResourceType>)>> {
    let mut by_group: BTreeMap<String, (String, Vec<K8sResourceType>)> = BTreeMap::new();
    let mut defined_by: BTreeMap<(String, String), String> = BTreeMap::new();

    for (source, resources) in per_source {
        for resource in resources {
            let coordinate = (resource.group.clone(), resource.kind.clone());

            if let Some(first) = defined_by.get(&coordinate) {
                anyhow::bail!(
                    "{}/{} is defined by both '{}' and '{}'.\n\
                     Two sources claiming one kind would make the generated type \
                     depend on which was read last. Exclude it from one of them.",
                    resource.group,
                    resource.kind,
                    first,
                    source
                );
            }

            defined_by.insert(coordinate, source.clone());

            match by_group.get_mut(&resource.group) {
                Some((owner, kinds)) if *owner == source => kinds.push(resource),
                Some((owner, _)) => anyhow::bail!(
                    "API group '{}' is defined by both '{}' and '{}'.\n\
                     Its types are written beside the floe that installs them, so two \
                     sources contributing to one group would be two floes claiming one \
                     file. Give the group one source.",
                    resource.group,
                    owner,
                    source
                ),
                None => {
                    by_group.insert(resource.group.clone(), (source.clone(), vec![resource]));
                }
            }
        }
    }

    Ok(by_group)
}

fn generate(config: GenerateConfig) -> Result<()> {
    let output_dir = Path::new(&config.output_dir);

    crate::io::fs::create_dir_all(output_dir.join("k8s"))
        .context("Failed to create k8s directory")?;

    let options = GeneratorOptions::default();
    let emitter_config = EmitterConfig::default();

    let mut k8s_versions = Vec::new();

    for (version, spec_path) in &config.k8s_versions {
        eprintln!(
            "{} Generating K8s types for {}",
            style(">>>").cyan(),
            version
        );

        let spec_content = crate::io::fs::read_to_string(spec_path)
            .with_context(|| format!("Failed to read spec file: {spec_path}"))?;

        let spec = parse_openapi_spec(&spec_content)
            .with_context(|| format!("Failed to parse OpenAPI spec: {spec_path}"))?;

        eprintln!("    Parsed {} definitions", spec.definitions.len());

        let type_set = convert_openapi_to_types(&spec, version, &options);
        eprintln!("    Found {} resources", type_set.resources.len());

        let nix_code = emit_k8s_types(&type_set, emitter_config.clone());

        let file_name = format!("{}.nix", version.replace('.', "_"));
        let file_path = output_dir.join("k8s").join(&file_name);
        crate::io::fs::write(&file_path, &nix_code)
            .with_context(|| format!("Failed to write {file_path:?}"))?;

        eprintln!("    Wrote {file_path:?}");
        k8s_versions.push(version.clone());
    }

    let mut per_source = Vec::new();

    for (name, crd_path) in &config.crds {
        eprintln!("{} Reading CRDs from {}", style(">>>").cyan(), name);

        let crd_content = crate::io::fs::read_to_string(crd_path)
            .with_context(|| format!("Failed to read CRD file: {crd_path}"))?;

        let resources = parse_crds_from_yaml(&crd_content, &options)
            .with_context(|| format!("Failed to parse CRD: {crd_path}"))?;

        eprintln!("    Found {} CRD types", resources.len());
        per_source.push((name.clone(), resources));
    }

    let by_group = group_by_api_group(per_source)?;

    // `<source>/crds/<group>.nix`, because the types live beside the floe that
    // installs the CRDs. The caller copies each source's directory into that
    // floe's, so the layout here is the layout there.
    for (group, (source, resources)) in &by_group {
        let nix_code = emit_crd_types(resources, emitter_config.clone());

        let dir = output_dir.join(source).join("crds");
        crate::io::fs::create_dir_all(&dir).with_context(|| format!("Failed to create {dir:?}"))?;

        let file_path = dir.join(format!("{group}.nix"));
        crate::io::fs::write(&file_path, &nix_code)
            .with_context(|| format!("Failed to write {file_path:?}"))?;

        eprintln!(
            "    {} {} kinds -> {file_path:?}",
            style(group).green(),
            resources.len()
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
        assert_eq!(config.k8s_versions.len(), 1);
        assert_eq!(
            config.k8s_versions.get("1.31").unwrap(),
            "/nix/store/abc/swagger.json"
        );
        assert_eq!(config.crds.len(), 1);
    }

    fn crd(group: &str, kind: &str) -> K8sResourceType {
        K8sResourceType::new(group.to_string(), "v1".to_string(), kind.to_string())
    }

    #[test]
    fn one_source_defining_several_groups_lands_in_a_file_each() {
        let grouped = group_by_api_group(vec![(
            "cert-manager".to_string(),
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
        let err = group_by_api_group(vec![
            ("a".to_string(), vec![crd("example.io", "Alpha")]),
            ("b".to_string(), vec![crd("example.io", "Beta")]),
        ])
        .unwrap_err()
        .to_string();

        assert!(err.contains("example.io"), "{err}");
        assert!(err.contains("'a'") && err.contains("'b'"), "{err}");
    }

    #[test]
    fn two_sources_claiming_one_kind_is_refused() {
        let err = group_by_api_group(vec![
            ("first".to_string(), vec![crd("example.io", "Thing")]),
            ("second".to_string(), vec![crd("example.io", "Thing")]),
        ])
        .unwrap_err()
        .to_string();

        assert!(err.contains("example.io/Thing"), "{err}");
        assert!(err.contains("'first'") && err.contains("'second'"), "{err}");
    }
}
