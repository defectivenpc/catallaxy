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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProvisionerConfig {
    pub k3d: K3dConfig,
    /// Talos gets its own block. It used to borrow `docker.clusterName`,
    /// which is the shared docker-daemon config and carries no lab prefix, so
    /// two labs with the same cluster name collided on container names.
    #[serde(default)]
    pub talos: TalosConfig,
    pub docker: DockerConfig,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DockerConfig {
    pub cluster_name: String,
    pub wait_timeout: String,
    pub colima: ColimaConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
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
                "docker": {
                    "clusterName": "catallaxy-app",
                    "waitTimeout": "10m",
                    "colima": { "enable": true, "profile": "catallaxy", "cpu": 4, "disk": 60, "memory": 8 },
                },
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
        assert_eq!(
            spec.provisioner_config.k3d.cluster_name,
            "minimal-local-app"
        );
        assert!(!spec.provisioner_config.k3d.no_flannel);
        assert_eq!(spec.provisioner_config.docker.colima.cpu, 4);
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
