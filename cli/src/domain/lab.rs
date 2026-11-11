use schemars::JsonSchema;
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::cluster::{ClusterDocument, DeliveryKind};
use super::plan::PlannedStep;
use super::secrets::SecretsSpec;

#[derive(Debug, Clone, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct InfraPublication {
    pub stack: String,
    /// Name of the output in the rendered stack, `<resource>_<output>`.
    pub output_name: String,
    pub store: String,
    pub key: String,
}

#[derive(Debug, Clone, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LabDocument {
    pub lab_name: String,

    pub cluster_names: Vec<String>,

    pub clusters: BTreeMap<String, ClusterDocument>,

    /// The ingress's host map: every hostname this lab answers for, keyed by
    /// the cluster that serves it.
    ///
    /// A cluster the lab does not front has no entry. That is the whole of
    /// how the difference is said — there was an `edges` block here carrying
    /// a three-valued mode, and the mode had to agree with whether the
    /// cluster exported its exposure to Nix at all.
    ///
    /// `verify` is what needs it: a hostname served by a cluster the lab does
    /// not front cannot be reached through the lab's ingress, and resolving
    /// it to loopback probes the wrong thing and reports the wrong failure.
    #[serde(default)]
    pub routed_hosts: BTreeMap<String, Vec<String>>,

    /// What each stack puts into a store once it has applied.
    ///
    /// Flattened on the Nix side, because the executor wants "for this stack,
    /// these outputs go to these places" and not a walk over resources.
    #[serde(default)]
    pub infra_publications: Vec<InfraPublication>,

    pub network: NetworkInfo,

    pub dns_info: Option<DnsInfo>,

    pub registry_port: Option<u16>,

    pub registry_upstreams: Vec<String>,

    pub lab_owned_registries: Vec<String>,

    pub ops_tool_path: Option<String>,

    pub cd: CdConfig,

    pub secrets: SecretsSpec,

    pub deployment_plan: Vec<PlannedStep>,

    pub teardown_plan: Vec<PlannedStep>,

    pub services: BTreeMap<String, HostService>,

    pub destroy: DestroyConfig,

    #[serde(default)]
    pub verify: super::verify::VerifyConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct NetworkInfo {
    pub name: String,
    pub docker_subnet: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct DnsInfo {
    pub host: String,
    pub port: u16,
    pub zone: String,
}

/// Where a cluster node should send lab hostname lookups.
///
/// Three states, because the two ways of having no address mean opposite
/// things to whoever writes `resolv.conf`: a lab that declares no host DNS is
/// working as designed and nodes fall through to docker's resolver, while a
/// lab that declares one and cannot be told its address has lost something it
/// asked for. Collapsing both into a missing address made the second
/// unreportable and the first report a problem that was not one.
pub enum LabDns {
    /// No host DNS in this lab. Lab hostnames are not expected to resolve.
    NotDeclared,
    /// The lab's DNS container, at this address.
    At(String),
    /// Declared, but its container address could not be found.
    Unresolved,
}

impl LabDns {
    /// Which of the three this lab is in, given a way to look up a container.
    ///
    /// The lookup is passed in rather than performed here: which address a
    /// container has is a question for the docker adapter, and the decision
    /// this makes is not.
    pub fn resolve(lab: &LabDocument, ip_of: impl FnOnce(&str) -> Option<String>) -> Self {
        match lab.dns_info.as_ref().and(lab.dns_container()) {
            None => Self::NotDeclared,
            Some(container) => ip_of(container).map_or(Self::Unresolved, Self::At),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct CdConfig {
    pub bootstrap: BootstrapTool,
    pub git: GitConfig,
}

/// Where `lab publish` pushes rendered manifests.
///
/// This was a `serde_json::Value` read through six `git_cfg.and_then(|g|
/// g["..."])` chains, each supplying its own default. The defaults are the
/// Nix option's to decide, and they are stated once here.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct GitConfig {
    #[serde(default)]
    pub repo: String,

    #[serde(default = "GitConfig::default_branch")]
    pub branch: String,

    /// Subdirectory within the repo. Empty means the root.
    #[serde(default)]
    pub path: String,

    #[serde(default = "GitConfig::default_provider")]
    pub provider: String,

    /// Open a pull request rather than pushing to `branch` directly.
    #[serde(default)]
    pub pr_enabled: bool,

    #[serde(default = "GitConfig::default_branch")]
    pub pr_base_branch: String,

    #[serde(default)]
    pub credential_from_kube_secret: Option<GitCredentialRef>,
}

impl GitConfig {
    fn default_branch() -> String {
        "main".to_string()
    }

    fn default_provider() -> String {
        "github".to_string()
    }
}

/// A Secret in some cluster holding the token `lab publish` pushes with.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct GitCredentialRef {
    pub context: String,
    pub namespace: String,
    pub name: String,

    #[serde(default = "GitCredentialRef::default_key")]
    pub key: String,

    pub username: String,
}

impl GitCredentialRef {
    fn default_key() -> String {
        "token".to_string()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum BootstrapTool {
    KubectlSsa,
    Helm,
    None,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct DestroyConfig {
    #[serde(default)]
    pub rescue_hints: BTreeMap<String, String>,
}

fn resolve_context<'a>(
    found: Option<&'a str>,
    cluster: &str,
    known: &[&str],
) -> anyhow::Result<&'a str> {
    match found {
        Some(context) if !context.is_empty() => Ok(context),
        Some(_) => anyhow::bail!(
            "cluster '{cluster}' has an empty runtime context, so the lab does \
             not know which kubectl context reaches it yet"
        ),
        None => anyhow::bail!(
            "cluster '{}' not found in lab (available: {})",
            cluster,
            known.join(", ")
        ),
    }
}

impl LabDocument {
    pub fn dns_container(&self) -> Option<&str> {
        self.services.get("dns").map(|s| s.container.as_str())
    }

    /// Whether anything in this lab mints the lab CA.
    ///
    /// Read off the plan rather than carried as a flag: the CA exists on disk
    /// because `cert-generate` put it there, so the step's presence is the
    /// fact, and a lab cannot declare one without the other.
    pub fn mints_lab_ca(&self) -> bool {
        self.deployment_plan
            .iter()
            .any(|step| matches!(step.params, crate::domain::plan::StepParams::CertGenerate(_)))
    }

    /// The zone whose registry hostname a node should be told to trust.
    ///
    /// Both halves have to hold. The trust config names
    /// `https://registry.<zone>` and verifies it against the lab CA, so
    /// without lab DNS the hostname never resolves and without the CA the
    /// `ca =` line points at a file that was never minted — a node told to
    /// trust it fails the pull it was supposed to enable.
    ///
    /// `None` is the ordinary answer for a lab that reaches its registry
    /// through the localhost mirror instead, which `minimal.local` does.
    pub fn registry_trust_zone(&self) -> Option<&str> {
        self.dns_info
            .as_ref()
            .filter(|_| self.mints_lab_ca())
            .map(|d| d.zone.as_str())
    }

    pub fn from_value(value: Value) -> Result<Self, serde_json::Error> {
        serde_json::from_value(value)
    }

    pub fn cluster(&self, name: &str) -> anyhow::Result<&ClusterDocument> {
        self.clusters.get(name).ok_or_else(|| {
            let available: Vec<&str> = self.clusters.keys().map(String::as_str).collect();
            anyhow::anyhow!(
                "cluster '{}' not found in lab (available: {})",
                name,
                available.join(", ")
            )
        })
    }

    /// Off the cluster's own handle. It used to come from a `runtimeContexts`
    /// map beside the clusters, which said the same thing a second time.
    pub fn kube_context(&self, cluster: &str) -> anyhow::Result<&str> {
        resolve_context(
            self.clusters
                .get(cluster)
                .map(|c| c.cluster_handle.context.as_str()),
            cluster,
            &self.clusters.keys().map(String::as_str).collect::<Vec<_>>(),
        )
    }

    /// Every answer this lab's clusters gave, once each, in order. One entry
    /// for the ordinary lab; two when a CD tool took one cluster over.
    pub fn delivery_kinds(&self) -> Vec<DeliveryKind> {
        let mut out: Vec<DeliveryKind> = Vec::new();
        for cluster in self.clusters.values() {
            if !out.contains(&cluster.delivery.kind) {
                out.push(cluster.delivery.kind);
            }
        }
        out
    }

    /// How this cluster's content reaches it, as its own delivery floe
    /// answered. It was one value for the whole lab, which is why two
    /// clusters delivering differently was an assertion rather than a thing
    /// to want.
    pub fn delivery_for(&self, cluster: &str) -> Option<DeliveryKind> {
        self.clusters.get(cluster).map(|c| c.delivery.kind)
    }

    /// Off the cluster's own content, which is where the namespaces its
    /// bundles create are already recorded.
    pub fn namespaces_for(&self, cluster: &str) -> &[String] {
        self.clusters
            .get(cluster)
            .map(|c| c.content.namespaces.as_slice())
            .unwrap_or(&[])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lab_json() -> Value {
        serde_json::json!({
            "labName": "minimal.local",
            "clusterNames": ["app"],
            "clusters": { "app": super::super::cluster::tests::cluster_json() },
            "routedHosts": {},
            "network": { "name": "minimal.local", "dockerSubnet": "172.20.0.0/16" },
            "dnsInfo": { "host": "127.0.0.1", "port": 5354, "zone": "minimal.test" },
            "registryPort": 5050,
            "registryUpstreams": ["docker.io"],
            "labOwnedRegistries": [],
            "opsToolPath": null,
            "cd": { "bootstrap": "kubectl-ssa", "git": {} },
            "secrets": {
                "envFile": null,
                "stores": {},
                "managed": {},
                "hostProjections": [],
            },
            "deploymentPlan": [],
            "teardownPlan": [],
            "services": {},
            "destroy": { "rescueHints": {} },
            "verify": {},
        })
    }

    #[test]
    fn a_lab_parses_from_the_config_nix_emits() {
        let lab = LabDocument::from_value(lab_json()).expect("lab spec parses");
        assert_eq!(lab.lab_name, "minimal.local");
        assert_eq!(lab.delivery_kinds(), vec![DeliveryKind::Kapp]);
        assert_eq!(lab.cd.bootstrap, BootstrapTool::KubectlSsa);
        assert_eq!(lab.dns_info.as_ref().unwrap().port, 5354);
        assert_eq!(lab.registry_port, Some(5050));
    }

    #[test]
    fn dns_and_registry_are_absent_when_the_lab_disables_them() {
        let mut json = lab_json();
        json["dnsInfo"] = Value::Null;
        json["registryPort"] = Value::Null;
        let lab = LabDocument::from_value(json).expect("a lab without dns or registry parses");
        assert!(lab.dns_info.is_none());
        assert!(lab.registry_port.is_none());
    }

    #[test]
    fn a_missing_cd_block_is_an_error_rather_than_a_kapp_guess() {
        let mut json = lab_json();
        json.as_object_mut().unwrap().remove("cd");
        assert!(
            LabDocument::from_value(json).is_err(),
            "cd is always emitted; defaulting it here would be a second source of truth"
        );
    }

    #[test]
    fn the_context_comes_from_runtime_contexts_which_a_pivot_rewrites() {
        let mut json = lab_json();
        json["clusters"]["app"]["clusterHandle"]["context"] = serde_json::json!("pivoted-app");
        let lab = LabDocument::from_value(json).unwrap();
        assert_eq!(lab.kube_context("app").unwrap(), "pivoted-app");
    }

    #[test]
    fn an_empty_runtime_context_is_reported_rather_than_guessed_at() {
        let mut json = lab_json();
        json["clusters"]["app"]["clusterHandle"]["context"] = serde_json::json!("");
        let lab = LabDocument::from_value(json).unwrap();
        let err = lab
            .kube_context("app")
            .expect_err("an empty context is not dialable");
        assert!(err.to_string().contains("empty runtime context"));
    }

    #[test]
    fn an_unknown_cluster_names_the_ones_that_exist() {
        let lab = LabDocument::from_value(lab_json()).unwrap();
        let err = lab
            .kube_context("nope")
            .expect_err("unknown cluster errors");
        assert!(err.to_string().contains("not found in lab"));
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct HostService {
    pub container: String,
    pub description: String,
    pub image: String,
    pub ports: Vec<String>,
    pub volumes: BTreeMap<String, ServiceVolume>,

    #[serde(default)]
    pub networks: Vec<String>,
    #[serde(default)]
    pub command: Vec<String>,
    #[serde(default)]
    pub extra_mounts: Vec<ExtraMount>,
    #[serde(default)]
    pub ready_probe: Option<ReadyProbe>,

    #[serde(default)]
    pub link: Option<String>,
    #[serde(default)]
    pub network_mode: Option<String>,
    #[serde(default)]
    pub cap_add: Vec<String>,
    #[serde(default)]
    pub network_config: Value,
    #[serde(default)]
    pub dns_containers: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ExtraMount {
    pub host: String,
    pub container: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceVolume {
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub persist: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReadyProbe {
    pub kind: String,
    pub host: String,
    pub port: u16,
    #[serde(default)]
    pub path: Option<String>,
    #[serde(default)]
    pub expected_status: Option<u16>,
    #[serde(default)]
    pub timeout: Option<String>,
}

#[cfg(test)]
mod schema {
    use super::LabDocument;

    /// The document is reflectable, which is what lets Nix be handed the same
    /// shape the parser enforces instead of a second description of it.
    ///
    /// Pinned at the top level only. The field *set* is the contract — a field
    /// added here is a field a floe may write — and the nested shapes are
    /// pinned where they are generated.
    #[test]
    fn the_document_reflects_every_block_the_parser_reads() {
        let schema = schemars::schema_for!(LabDocument);
        let json = serde_json::to_value(&schema).expect("schema serialises");

        let mut props: Vec<&str> = json["properties"]
            .as_object()
            .expect("an object schema")
            .keys()
            .map(String::as_str)
            .collect();
        props.sort_unstable();

        assert_eq!(
            props,
            [
                "cd",
                "clusterNames",
                "clusters",
                "deploymentPlan",
                "destroy",
                "dnsInfo",
                "infraPublications",
                "labName",
                "labOwnedRegistries",
                "network",
                "opsToolPath",
                "registryPort",
                "registryUpstreams",
                "routedHosts",
                "secrets",
                "services",
                "teardownPlan",
                "verify"
            ]
        );
    }
}
