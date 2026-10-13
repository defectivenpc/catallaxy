pub mod extract;
pub mod render;

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LabTopology {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zone: Option<String>,
    pub cd_strategy: String,
    pub network: LabNetwork,
    pub services: BTreeMap<String, LabService>,
    pub clusters: BTreeMap<String, ClusterTopology>,
    pub edges: Vec<TopologyEdge>,
    pub endpoints: Vec<Endpoint>,
    pub deployment_plan: Vec<PlanStep>,
}

/// A hostname this lab serves, and what to type to reach it.
///
/// Assembled from what the clusters route and what the host services publish,
/// which is the same pair `verify` probes — the difference being that this
/// reports and does not dial, so it answers with the lab down.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Endpoint {
    pub host: String,
    pub cluster: String,
    pub tier: String,
    /// `https://git.homelab.test`, once the host resolves the zone.
    pub url: String,
    /// What reaches it without touching the host's resolver.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub direct: Option<String>,
    /// Set when the lab's ingress cannot reach it at all — a cluster that is
    /// its own edge. Reported rather than omitted, so a host never disappears
    /// from the list without saying why.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unreachable: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LabNetwork {
    pub name: String,
    pub docker_subnet: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LabService {
    pub description: String,
    pub container: String,
    pub ports: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub running: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterTopology {
    pub name: String,
    pub provider: String,
    pub kube_context: String,
    pub control_planes: u64,
    pub workers: u64,
    pub pod_subnet: String,
    pub service_subnet: String,
    pub components: BTreeMap<String, ComponentSummary>,

    /// The namespaces this cluster's content declares, with how each one is
    /// doing once something has looked. Health used to be per component,
    /// against a namespace guessed from the unit's name.
    pub namespaces: BTreeMap<String, Option<ComponentHealthState>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub live: Option<ClusterLiveState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentSummary {
    /// How many of this unit's bundles are in the install order.
    pub bundles: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "status")]
pub enum ComponentHealthState {
    #[serde(rename = "healthy")]
    Healthy { pod_count: usize },
    #[serde(rename = "degraded")]
    Degraded { ready: usize, total: usize },
    #[serde(rename = "no_pods")]
    NoPods,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClusterLiveState {
    pub reachable: bool,
    pub nodes: Vec<NodeSummary>,
    pub kapp_apps: Vec<KappAppSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeSummary {
    pub name: String,
    pub ready: bool,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KappAppSummary {
    pub name: String,
    pub status: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub age: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TopologyEdge {
    pub kind: EdgeKind,
    pub source: String,
    pub target: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EdgeKind {
    ProxyRoute,
    DeployDependency,
    Provisions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanStep {
    pub step_type: String,
    pub description: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, clap::ValueEnum)]
#[clap(rename_all = "lowercase")]
pub enum TopologyFormat {
    Json,
    Table,
    Mermaid,
    Dot,
}
