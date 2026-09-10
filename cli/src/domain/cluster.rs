use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// One Secret a cluster builds out of a store's values.
///
/// Was `serde_json::Value` on `ClusterSpec`, decoded by `parse_projections`,
/// which printed a warning and returned an empty map when the decode failed —
/// so a misconfigured projection produced no Secret and no error, and the
/// deploy went on to fail wherever that Secret was mounted.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectionConfig {
    pub source: String,
    pub namespace: String,
    pub keys: BTreeMap<String, ProjectionKeyConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectionKeyConfig {
    pub from: String,
    pub transform: Option<String>,
    pub json_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClusterSpec {
    pub name: String,

    pub lab_name: String,

    pub provisioner: ProvisionerKind,

    pub provider: String,

    pub kube_context: String,

    pub kubernetes: KubernetesSpec,

    pub network: ClusterNetwork,

    pub deploy: DeploySpec,

    pub lifecycle: Lifecycle,

    pub provisioner_config: ProvisionerConfig,

    /// What the operator's machine contributes. `#[serde(default)]` because
    /// a lab that names no timeout and runs no VM has nothing to say here.
    #[serde(default)]
    pub host: HostConfig,

    /// Who fronts this cluster — RFC 0005 §6.4.
    #[serde(default)]
    pub edge: EdgeSpec,

    pub floes: BTreeMap<String, FloeSpec>,

    pub exposed_hosts: Vec<ExposedHost>,

    #[serde(default)]
    pub projections: BTreeMap<String, ProjectionConfig>,

    #[serde(default)]
    pub trust: ClusterTrust,

    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

/// Where this cluster wants the lab's CA certificate to appear.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClusterTrust {
    #[serde(default)]
    pub ca_config_maps: Vec<CaConfigMap>,
}

/// One ConfigMap key the lab CA should be written to.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CaConfigMap {
    pub namespace: String,
    pub name: String,
    pub key: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProvisionerKind {
    K3d,
    Talos,
    Crossplane,
    External,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KubernetesSpec {
    pub distribution: String,
    pub version: String,
    pub control_planes: u32,
    pub workers: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClusterNetwork {
    pub pod_subnet: String,
    pub service_subnet: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeploySpec {
    pub strategy: DeployStrategy,

    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DeployStrategy {
    Kapp,
    Argocd,
    Fleet,
}

impl DeployStrategy {
    pub fn tag(self) -> &'static str {
        match self {
            DeployStrategy::Kapp => "kapp",
            DeployStrategy::Argocd => "argocd",
            DeployStrategy::Fleet => "fleet",
        }
    }

    pub fn is_gitops(self) -> bool {
        match self {
            DeployStrategy::Kapp => false,
            DeployStrategy::Argocd | DeployStrategy::Fleet => true,
        }
    }
}

/// How this cluster is made, and the settings for that one way.
///
/// Externally tagged, which is serde's default for an enum and exactly what
/// `T.taggedUnion` in `lib/floe-core/types.nix` emits: `{"k3d": {…}}`. One
/// key, named for the variant.
///
/// It was a struct with one required field per provisioner, so a cluster made
/// any other way still had to carry a k3d block — which made the comment on
/// `floes/provisioners/k3d-cluster.nix` saying "the provisioner is not a
/// closed set" true of the floe and false of what it emitted. Worse, the
/// block sat beside a `provisioner` tag that could contradict it, and a spec
/// tagged `talos` carrying k3d settings parsed perfectly.
///
/// Variants arrive with the provisioners that emit them. An absent one is a
/// parse error naming the variant, which is the point: `#[serde(default)]` on
/// a Talos block meant a missing one became an empty one and failed later, on
/// a missing cluster name, somewhere that could not say why.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ProvisionerConfig {
    K3d(K3dConfig),
    Talos(TalosConfig),
    External(ExternalConfig),
}

/// A cluster something else brings into existence.
///
/// `cata` creates nothing for one of these. `madeBy` is free text for the
/// operator reading a plan and is never dispatched on — dispatching on it
/// would make it a provisioner enum again, which is the shape this whole
/// type replaced.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExternalConfig {
    pub made_by: String,
}

impl ProvisionerConfig {
    /// The provisioner this config is for.
    ///
    /// `ClusterSpec::provisioner` carries the same fact, because the plan
    /// steps and the lab document name it as a string. Derived from one place
    /// on the Nix side (the union's key) so the two cannot disagree;
    /// `spec_provisioner_agrees_with_its_config` holds the line here.
    pub fn kind(&self) -> ProvisionerKind {
        match self {
            ProvisionerConfig::K3d(_) => ProvisionerKind::K3d,
            ProvisionerConfig::Talos(_) => ProvisionerKind::Talos,
            ProvisionerConfig::External(_) => ProvisionerKind::External,
        }
    }

    /// The k3d settings, when this is a k3d cluster.
    ///
    /// Callers that only want to know "is there anything to do here" get
    /// `None` for every other provisioner rather than an empty k3d block that
    /// would read as "k3d, configured with nothing".
    pub fn k3d(&self) -> Option<&K3dConfig> {
        match self {
            ProvisionerConfig::K3d(c) => Some(c),
            ProvisionerConfig::Talos(_) | ProvisionerConfig::External(_) => None,
        }
    }

    /// Every host port this cluster's provisioner publishes.
    ///
    /// The preflight compares these against the lab's services, and it has to
    /// work for a provisioner it was not written with in mind — so the match
    /// lives here, once, rather than at the call site chaining one accessor
    /// per variant.
    pub fn published_ports(&self) -> &[String] {
        match self {
            ProvisionerConfig::K3d(c) => &c.ports,
            ProvisionerConfig::Talos(c) => &c.exposed_ports,
            // Nothing on this host publishes a port for it.
            ProvisionerConfig::External(_) => &[],
        }
    }

    /// Manifests the provisioner applies before the node is Ready.
    ///
    /// Empty for a provisioner with no such mechanism, which is a real answer
    /// and not a missing one: it means nothing was applied that way.
    pub fn auto_deploy_manifests(&self) -> &[AutoDeployManifest] {
        match self {
            ProvisionerConfig::K3d(c) => &c.auto_deploy_manifests,
            ProvisionerConfig::Talos(_) | ProvisionerConfig::External(_) => &[],
        }
    }
}

/// Who fronts this cluster, and where.
///
/// `verify` needs it: a hostname routed by a cluster the lab is *not* the edge
/// for cannot be reached through the lab's proxy, and resolving it to loopback
/// probes the wrong thing and reports the wrong failure.
///
/// Defaults to `proxy` with no backend so an older lab document still parses.
/// That combination is refused at evaluation, so it cannot arrive from Nix.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EdgeSpec {
    pub mode: EdgeMode,
    pub backend: Option<String>,
    pub http_port: u16,
    pub https_port: u16,
}

impl Default for EdgeSpec {
    fn default() -> Self {
        EdgeSpec {
            mode: EdgeMode::Proxy,
            backend: None,
            http_port: 80,
            https_port: 443,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EdgeMode {
    /// The lab fronts this cluster, at `backend`.
    #[default]
    Proxy,
    /// The cluster is its own edge; the lab routes nothing to it.
    #[serde(rename = "self")]
    Own,
    /// Nothing routes to this cluster at all.
    None,
}

/// What the operator's machine contributes, as opposed to the provisioner.
///
/// Colima is a VM the operator runs and the timeout is how long this lab is
/// willing to wait; k3d is told neither. They lived under
/// `provisionerConfig.docker` beside a `clusterName` that nothing read.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostConfig {
    pub wait_timeout: String,
    #[serde(default)]
    pub colima: ColimaConfig,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TalosConfig {
    pub cluster_name: String,
    pub image: Option<String>,
    pub kubernetes_version: Option<String>,
    pub subnet: String,
    pub exposed_ports: Vec<String>,
    pub mounts: Vec<String>,
    pub memory: String,
    pub cpus: String,
    /// Machine config patches. Talos is configured through these rather than
    /// through flags: registry mirrors, CA trust, nameservers, API server
    /// arguments and the CNI choice are all machine config.
    pub config_patches: Vec<String>,
    /// Containers attached to the cluster's own docker network once it
    /// exists. talosctl will not join an existing network, and kube-proxy
    /// will not serve a NodePort on an interface added after the fact, so
    /// whatever has to reach the cluster joins its network instead.
    #[serde(default)]
    pub reachable_from: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct K3dConfig {
    pub cluster_name: String,
    pub image: Option<String>,
    pub network: Option<String>,
    pub no_traefik: bool,
    #[serde(rename = "noServiceLB")]
    pub no_service_lb: bool,
    pub no_flannel: bool,
    pub no_local_storage: bool,
    pub ports: Vec<String>,
    pub extra_api_server_args: Vec<String>,
    pub extra_volumes: Vec<ExtraVolume>,
    pub auto_deploy_manifests: Vec<AutoDeployManifest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExtraVolume {
    pub host_path: String,
    pub container_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AutoDeployManifest {
    pub name: String,
    pub path: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ColimaConfig {
    pub enable: bool,
    pub profile: String,
    pub cpu: u64,
    pub memory: u64,
    pub disk: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Lifecycle {
    #[serde(default)]
    pub pre_provision: Vec<Hook>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Hook {
    pub name: String,
    pub description: String,
    pub bin: String,
    #[serde(default)]
    pub order: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FloeSpec {
    pub enable: bool,

    #[serde(default)]
    pub namespace: Option<String>,

    #[serde(default)]
    pub version: Option<String>,

    #[serde(default)]
    pub domain: Option<String>,

    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExposedHost {
    pub host: String,
    pub namespace: String,
    pub bundle: String,
    pub tier: String,
    #[serde(default)]
    pub paths: Vec<String>,
}

impl ExposedHost {
    /// Where to ask this host whether it is serving.
    ///
    /// The root when the route has a rule for it, and the first rule's prefix
    /// otherwise. Taking the first unconditionally reads whichever rule the
    /// floe happened to write first, which is fine for the single-rule routes
    /// every floe had until netbird — and wrong for a route that fans one
    /// hostname out across several backends by path. netbird's first rule is
    /// `/api`, and a bare GET of an API's prefix is a 404: not "the gateway
    /// has no route", which is what the probe is trying to detect, but "there
    /// is no page there", which it cannot tell apart.
    ///
    /// The root is the honest place to ask, because a host that serves
    /// anything at all usually serves something there — and where it does
    /// not, the route says so by having no `/` rule.
    pub fn probe_path(&self) -> &str {
        if self.paths.iter().any(|p| p == "/") {
            return "/";
        }
        self.paths.first().map_or("/", |p| p.as_str())
    }
}

impl ClusterSpec {
    pub fn from_value(value: Value) -> Result<Self, serde_json::Error> {
        serde_json::from_value(value)
    }

    pub fn enabled_floes(&self) -> impl Iterator<Item = (&String, &FloeSpec)> {
        self.floes.iter().filter(|(_, f)| f.enable)
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// A spec as the Nix layer actually emits one. Shared so other modules
    /// test against the real shape rather than a hand-built approximation.
    pub(crate) fn cluster_json() -> Value {
        serde_json::json!({
            "name": "app",
            "labName": "minimal.local",
            "provisioner": "k3d",
            "provider": "docker",
            "kubeContext": "k3d-minimal-local-app",
            "kubernetes": {
                "distribution": "k3s",
                "version": "1.31",
                "controlPlanes": 1,
                "workers": 0,
            },
            "network": { "podSubnet": "10.244.0.0/16", "serviceSubnet": "10.96.0.0/12" },
            "deploy": { "strategy": "kapp", "argocd": {}, "fleet": {}, "kapp": {} },
            "lifecycle": { "preProvision": [] },
            "provisionerConfig": {
                "k3d": {
                    "clusterName": "minimal-local-app",
                    "image": "rancher/k3s:v1.31.4-k3s1",
                    "network": "minimal.local",
                    "noTraefik": true,
                    "noServiceLB": false,
                    "noLocalStorage": false,
                    "noFlannel": false,
                    "ports": [],
                    "extraApiServerArgs": [],
                    "extraVolumes": [],
                    "autoDeployManifests": [],
                },
            },
            "host": {
                "waitTimeout": "10m",
                "colima": { "enable": true, "profile": "catallaxy", "cpu": 4, "disk": 60, "memory": 8 },
            },
            "floes": {
                "cert-manager": { "enable": true, "namespace": "cert-manager", "version": "v1.16.1", "domain": "" },
                "argocd": { "enable": false, "namespace": "argocd", "version": "", "domain": "" },
            },
            "exposedHosts": [],
            "projections": {},
        })
    }

    #[test]
    fn a_cluster_parses_from_the_config_nix_emits() {
        let spec = ClusterSpec::from_value(cluster_json()).expect("cluster spec parses");
        assert_eq!(spec.provisioner, ProvisionerKind::K3d);
        assert_eq!(spec.kube_context, "k3d-minimal-local-app");
        assert_eq!(spec.kubernetes.workers, 0);
        assert_eq!(spec.deploy.strategy, DeployStrategy::Kapp);
    }

    #[test]
    fn the_provisioner_config_carries_what_nix_computed() {
        let spec = ClusterSpec::from_value(cluster_json()).unwrap();
        let k3d = spec.provisioner_config.k3d().expect("a k3d cluster");
        assert_eq!(k3d.cluster_name, "minimal-local-app");
        assert!(!k3d.no_flannel);
        assert_eq!(spec.host.colima.cpu, 4);
    }

    /// The tag and the block are one fact on the Nix side — `provisioner` is
    /// read off the union's key in `modules/lab/cluster.nix` — and this is
    /// where that stays true after the wire.
    #[test]
    fn spec_provisioner_agrees_with_its_config() {
        let spec = ClusterSpec::from_value(cluster_json()).unwrap();
        assert_eq!(spec.provisioner, spec.provisioner_config.kind());
    }

    /// Two variants at once is not a `ProvisionerConfig`. Serde's
    /// externally-tagged representation refuses it for the same reason
    /// `T.taggedUnion` does, so the refusal holds on both sides of the wire.
    #[test]
    fn a_config_naming_two_provisioners_is_refused() {
        let mut json = cluster_json();
        json["provisionerConfig"]["talos"] = serde_json::json!({ "clusterName": "x" });
        assert!(ClusterSpec::from_value(json).is_err());
    }

    #[test]
    fn only_enabled_floes_are_listed() {
        let spec = ClusterSpec::from_value(cluster_json()).unwrap();
        let names: Vec<&str> = spec.enabled_floes().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["cert-manager"]);
    }

    #[test]
    fn a_provisioner_nix_does_not_declare_is_rejected() {
        let mut json = cluster_json();
        json["provisioner"] = serde_json::json!("kubeadm");
        let err = ClusterSpec::from_value(json).expect_err("unknown provisioner must not parse");
        assert!(
            err.to_string().contains("kubeadm"),
            "the error should name the offending value, got: {err}"
        );
    }

    #[test]
    fn a_missing_kube_context_is_an_error_rather_than_a_guess() {
        let mut json = cluster_json();
        json.as_object_mut().unwrap().remove("kubeContext");
        assert!(
            ClusterSpec::from_value(json).is_err(),
            "kubeContext is always emitted; its absence means the contract broke"
        );
    }

    fn exposed(paths: &[&str]) -> ExposedHost {
        ExposedHost {
            host: "netbird.homelab.test".into(),
            namespace: "netbird".into(),
            bundle: "netbird/server".into(),
            tier: "public".into(),
            paths: paths.iter().map(|p| (*p).into()).collect(),
        }
    }

    /// netbird fans one hostname across five backends and writes `/api`
    /// first. Probing that answers 404, which is also what a gateway with no
    /// route answers — so the check cannot tell "no page here" from "no route
    /// at all", and reported a working mesh as broken.
    #[test]
    fn a_multi_rule_route_is_probed_at_its_root() {
        let host = exposed(&["/api", "/management.ManagementService/", "/relay", "/"]);
        assert_eq!(host.probe_path(), "/");
    }

    /// A host that genuinely serves only a prefix says so by having no `/`
    /// rule, and is probed where it does serve.
    #[test]
    fn a_route_with_no_root_is_probed_where_it_answers() {
        assert_eq!(exposed(&["/api"]).probe_path(), "/api");
    }

    /// The single-rule case every other floe renders.
    #[test]
    fn a_route_with_no_paths_at_all_is_probed_at_the_root() {
        assert_eq!(exposed(&[]).probe_path(), "/");
    }

    #[test]
    fn every_provisioner_the_module_declares_round_trips() {
        for tag in ["k3d", "talos", "crossplane", "external"] {
            let mut json = cluster_json();
            json["provisioner"] = serde_json::json!(tag);
            let spec = ClusterSpec::from_value(json)
                .unwrap_or_else(|e| panic!("provisioner '{tag}' should parse: {e}"));
            assert_eq!(
                serde_json::to_value(spec.provisioner).unwrap(),
                serde_json::json!(tag)
            );
        }
    }
}
