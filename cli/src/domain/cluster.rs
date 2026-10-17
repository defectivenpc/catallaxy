use schemars::JsonSchema;
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// One Secret a cluster builds out of a store's values.
///
/// Was `serde_json::Value` on `ClusterSpec`, decoded by `parse_projections`,
/// which printed a warning and returned an empty map when the decode failed —
/// so a misconfigured projection produced no Secret and no error, and the
/// deploy went on to fail wherever that Secret was mounted.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProjectionConfig {
    pub source: String,
    pub namespace: String,
    pub keys: BTreeMap<String, ProjectionKeyConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ProjectionKeyConfig {
    pub from: String,
    pub transform: Option<String>,
    pub json_key: Option<String>,
}

/// One cluster, as `cata` is handed it.
///
/// Four blocks, and only the first two are the cluster: it *denotes* a cluster
/// handle and its content. `provisioning` is the function that establishes the
/// handle
/// and `delivery` is the one that converges the content onto it, carried here
/// because `cata` is what applies them and has to be told which.
/// `docs/cluster-spec.md` is the derivation.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ClusterSpec {
    pub cluster_handle: ClusterHandle,
    pub provisioning: Provisioning,
    pub content: Content,
    pub delivery: Delivery,
}

/// What can be observed of a cluster that already exists.
///
/// The membership rule is observability, which is decidable because
/// `cluster_shape` already runs it: a field belongs here exactly when drift
/// detection could compare it against a running cluster. `provider` used to
/// sit beside these and held `"docker"` or `"external"` — read only to be
/// printed, and already carried by the provisioning union's own key.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ClusterHandle {
    pub name: String,

    /// Unique on the host that holds it. A composition holding two clusters
    /// supplies it; the cluster's own name is the default.
    pub instance_name: String,

    pub context: String,

    pub kubernetes: KubernetesSpec,

    pub network: ClusterNetwork,
}

/// What establishes the handle: which tool, with which arguments.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Provisioning {
    /// Externally tagged, so the key *is* the tool. A second field naming it
    /// could disagree with the block beside it.
    pub config: ProvisionerConfig,

    #[serde(default)]
    pub hooks: Vec<Hook>,

    /// How long this host waits for an API server to answer. Not the wait for
    /// an apply to settle, which belongs to `delivery` and had the same name.
    pub wait: String,
}

/// The desired state: what the components fold up to.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Content {
    /// The rendered waves, as a path. A document carrying the resources
    /// themselves would put every object into the thing every `nix eval` has
    /// to serialise; carrying where they are is what lets `cata cluster up`
    /// act on a cluster with no lab to look inside.
    pub tree: String,

    /// Which namespaces are the lab's, so pruning knows what it may delete.
    pub namespaces: Vec<String>,

    /// The install order, as names and probe flags rather than the resources
    /// themselves: `plan-manifests` prints it without building the tree. A
    /// cache of what the rendered tree says, and checked against it.
    pub waves: Vec<Vec<WaveBundle>>,

    pub exposed_hosts: Vec<ExposedHost>,

    #[serde(default)]
    pub projections: BTreeMap<String, ProjectionConfig>,
}

/// One bundle, as the wave summary carries it.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WaveBundle {
    pub name: String,
    pub has_ready_probe: bool,
    pub resource_count: usize,
}

/// How content reaches the handle.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Delivery {
    pub strategy: DeployStrategy,

    /// How long an apply may take to settle. The other half of what one
    /// `waitTimeout` used to mean.
    pub wait_timeout: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum ProvisionerKind {
    K3d,
    Talos,
    External,
}

impl ProvisionerKind {
    /// The word a human reads, which is the union's own key. `provider` used
    /// to carry it as a separate string, so the two could disagree.
    pub fn tag(self) -> &'static str {
        match self {
            Self::K3d => "k3d",
            Self::Talos => "talos",
            Self::External => "external",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct KubernetesSpec {
    pub distribution: String,
    pub version: String,
    pub control_planes: u32,
    pub workers: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ClusterNetwork {
    pub pod_subnet: String,
    pub service_subnet: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
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
/// `T.taggedUnion` in the floe library's `types.nix` emits: `{"k3d": {…}}`. One
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
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
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
#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
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

/// What the operator's machine contributes, as opposed to the provisioner.
///
/// Colima is a VM the operator runs and the timeout is how long this lab is
/// willing to wait; k3d is told neither. They lived under
#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct K3dConfig {
    pub cluster_name: String,
    pub image: Option<String>,
    pub network: Option<String>,

    /// The host service whose state directory holds the containerd config a
    /// node pulls through — `registries.yaml`, `certs.d/` and
    /// `lab-resolv.conf`. `None` for a cluster that does not mirror.
    ///
    /// A name and not a path: the path is this crate's to build and already
    /// was. What it could not do was know *which* service, so `create_cluster`
    /// joined a literal `"registry"` and probed for the files — which made
    /// mirroring something discovered on the filesystem rather than something
    /// the cluster declared. A stale directory mounted a mirror nobody asked
    /// for; a cluster whose `registry-setup` had not run mounted none and said
    /// nothing.
    ///
    /// Defaulted, so a record written before this field existed describes a
    /// cluster that was given no mirror.
    #[serde(default)]
    pub node_config_from: Option<String>,
    pub no_traefik: bool,
    #[serde(rename = "noServiceLB")]
    pub no_service_lb: bool,
    pub no_flannel: bool,
    pub no_local_storage: bool,
    pub ports: Vec<String>,
    pub extra_api_server_args: Vec<String>,
    /// Defaulted rather than versioned, for the same reason as
    /// `no_local_storage`: a record written before this field existed describes
    /// a cluster that was given no extra server args, and `[]` says exactly
    /// that.
    #[serde(default)]
    pub extra_k3s_args: Vec<K3sArg>,
    pub extra_volumes: Vec<ExtraVolume>,
    pub auto_deploy_manifests: Vec<AutoDeployManifest>,
}

/// A flag handed to `k3s server` itself, rather than to one of the components
/// it supervises. `extra_api_server_args` reaches only kube-apiserver; this
/// reaches k3s, which is where `--datastore-endpoint` and its siblings live.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct K3sArg {
    pub arg: String,
    /// k3d's node selector — `server:*`, `agent:0`, and so on. Carried rather
    /// than assumed: an arg meant for every server and one meant for a single
    /// agent are different instructions, and k3d has no default.
    pub scope: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ExtraVolume {
    pub host_path: String,
    pub container_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct AutoDeployManifest {
    pub name: String,
    pub path: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ColimaConfig {
    pub enable: bool,
    pub profile: String,
    pub cpu: u64,
    pub memory: u64,
    pub disk: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Hook {
    pub name: String,
    pub description: String,
    pub bin: String,
    #[serde(default)]
    pub order: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
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
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// A document as the Nix layer actually emits one. Shared so other
    /// modules test against the real shape rather than a hand-built
    /// approximation.
    pub(crate) fn cluster_json() -> Value {
        serde_json::json!({
            "clusterHandle": {
                "name": "app",
                "instanceName": "minimal-local-app",
                "context": "k3d-minimal-local-app",
                "kubernetes": {
                    "distribution": "k3s",
                    "version": "1.31",
                    "controlPlanes": 1,
                    "workers": 0,
                },
                "network": { "podSubnet": "10.244.0.0/16", "serviceSubnet": "10.96.0.0/12" },
            },
            "provisioning": {
                "config": {
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
                "hooks": [],
                "wait": "10m",
            },
            "content": {
                "tree": "/nix/store/0000000000000000000000000000000-manifests",
                "namespaces": ["cert-manager"],
                "waves": [[{ "name": "cert-manager/crds", "hasReadyProbe": false, "resourceCount": 3 }]],
                "exposedHosts": [],
                "projections": {},
            },
            "delivery": { "strategy": "kapp", "waitTimeout": "10m" },
        })
    }

    #[test]
    fn a_cluster_parses_from_the_document_nix_emits() {
        let spec = ClusterSpec::from_value(cluster_json()).expect("cluster document parses");
        assert_eq!(spec.provisioning.config.kind(), ProvisionerKind::K3d);
        assert_eq!(spec.cluster_handle.context, "k3d-minimal-local-app");
        assert_eq!(spec.cluster_handle.kubernetes.workers, 0);
        assert_eq!(spec.delivery.strategy, DeployStrategy::Kapp);
    }

    #[test]
    fn the_provisioning_config_carries_what_nix_computed() {
        let spec = ClusterSpec::from_value(cluster_json()).unwrap();
        let k3d = spec.provisioning.config.k3d().expect("a k3d cluster");
        assert_eq!(k3d.cluster_name, "minimal-local-app");
        assert!(!k3d.no_flannel);
    }

    /// The two waits one `waitTimeout` used to mean, now each on the process
    /// that does the waiting.
    #[test]
    fn the_two_waits_are_separate_fields() {
        let spec = ClusterSpec::from_value(cluster_json()).unwrap();
        assert_eq!(spec.provisioning.wait, "10m");
        assert_eq!(spec.delivery.wait_timeout, "10m");
    }

    /// Only the handle carries what could be observed of a running cluster, so
    /// a field of it missing is a parse error rather than a default that
    /// reads as a fact.
    #[test]
    fn a_handle_missing_a_field_is_refused() {
        let mut json = cluster_json();
        json["clusterHandle"]
            .as_object_mut()
            .unwrap()
            .remove("instanceName");
        assert!(ClusterSpec::from_value(json).is_err());
    }

    /// Two variants at once is not a `ProvisionerConfig`. Serde's
    /// externally-tagged representation refuses it for the same reason
    /// `T.taggedUnion` does, so the refusal holds on both sides of the wire.
    #[test]
    fn a_config_naming_two_provisioners_is_refused() {
        let mut json = cluster_json();
        json["provisioning"]["config"]["talos"] = serde_json::json!({ "clusterName": "x" });
        assert!(ClusterSpec::from_value(json).is_err());
    }

    #[test]
    fn a_provisioner_nix_does_not_declare_is_rejected() {
        let mut json = cluster_json();
        json["provisioning"]["config"] = serde_json::json!({ "kubeadm": {} });
        let err = ClusterSpec::from_value(json).expect_err("unknown provisioner must not parse");
        assert!(
            err.to_string().contains("kubeadm"),
            "the error should name the offending value, got: {err}"
        );
    }

    #[test]
    fn a_missing_context_is_an_error_rather_than_a_guess() {
        let mut json = cluster_json();
        json["clusterHandle"]
            .as_object_mut()
            .unwrap()
            .remove("context");
        assert!(
            ClusterSpec::from_value(json).is_err(),
            "the cluster_handle's context is always emitted; its absence means the contract broke"
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

    /// Every variant the module declares, round-tripped through the key that
    /// names it. There is no second field to disagree with the block now, so
    /// what this holds is that each variant parses and reports itself.
    #[test]
    fn every_provisioner_the_module_declares_round_trips() {
        let blocks = [
            (
                "k3d",
                cluster_json()["provisioning"]["config"]["k3d"].clone(),
            ),
            (
                "talos",
                serde_json::to_value(TalosConfig::default()).unwrap(),
            ),
            (
                "external",
                serde_json::json!({ "madeBy": "someone else", "kubeconfigFrom": null }),
            ),
        ];

        for (tag, block) in blocks {
            let mut json = cluster_json();
            json["provisioning"]["config"] = serde_json::json!({ tag: block });
            let spec = ClusterSpec::from_value(json)
                .unwrap_or_else(|e| panic!("provisioner '{tag}' should parse: {e}"));
            assert_eq!(
                serde_json::to_value(spec.provisioning.config.kind()).unwrap(),
                serde_json::json!(tag)
            );
        }
    }
}
