pub mod checks;

use serde::Serialize;

use crate::domain::LabSpec;
pub use crate::domain::diagnostic::{Diagnostic, Severity};

pub const CHECK_NAMES: [&str; 6] = [
    "clusters",
    "services",
    "rollouts",
    "endpoints",
    "certificates",
    "chainsaw",
];

pub use crate::domain::verify::{DeclaredCheck, EndpointPolicy, VerifyConfig};

pub use crate::domain::ExposedHost;

pub struct VerifyContext<'a> {
    pub lab_name: &'a str,
    pub lab: &'a LabSpec,
    pub config: &'a VerifyConfig,
    pub package: Option<&'a std::path::Path>,
}

impl VerifyContext<'_> {
    pub fn context_for(&self, cluster: &str) -> Option<&str> {
        self.lab.kube_context(cluster).ok()
    }

    pub fn namespaces_for(&self, cluster: &str) -> &[String] {
        self.lab.namespaces_for(cluster)
    }

    /// Whether the lab's ingress answers for this hostname.
    ///
    /// Asked per host rather than per cluster, because the host map is what
    /// the ingress was built from: a `use_backend` line exists for exactly
    /// these names. A cluster the lab does not front has no entry at all,
    /// which is how "not ours to probe" is said.
    fn routes(&self, cluster: &str, host: &str) -> bool {
        self.lab
            .routed_hosts
            .get(cluster)
            .is_some_and(|hosts| hosts.iter().any(|h| h == host))
    }

    /// Every routed hostname the lab's ingress can be asked about.
    ///
    /// Hostnames it does not answer for are left out: they do not resolve
    /// through the lab, so probing them at its ingress tests a route nobody
    /// declared and fails for the wrong reason.
    pub fn exposed_hosts(&self) -> Vec<(String, ExposedHost)> {
        let mut out = self.hosts_where(|ctx, cluster, host| ctx.routes(cluster, host));
        out.dedup_by(|a, b| a.1.host == b.1.host);
        out
    }

    /// Routed hostnames the lab's ingress cannot be asked about.
    ///
    /// `exposed_hosts` drops these for a good reason — probing them at the
    /// lab's ingress would fail for the wrong reason — but dropping them
    /// silently meant `verified` was reported about hosts nothing looked at.
    /// Naming them is not the discovery intended here; it is the
    /// difference between silence and a stated skip, which is what a report
    /// claiming success owes the reader.
    pub fn unreachable_hosts(&self) -> Vec<(String, ExposedHost)> {
        self.hosts_where(|ctx, cluster, host| !ctx.routes(cluster, host))
    }

    fn hosts_where(&self, keep: impl Fn(&Self, &str, &str) -> bool) -> Vec<(String, ExposedHost)> {
        let mut out: Vec<(String, ExposedHost)> = self
            .lab
            .clusters
            .iter()
            .flat_map(|(cluster, spec)| {
                spec.content
                    .exposed_hosts
                    .iter()
                    .map(move |host| (cluster.clone(), host.clone()))
            })
            .filter(|(cluster, host)| keep(self, cluster, &host.host))
            .collect();
        out.sort_by(|a, b| a.1.host.cmp(&b.1.host));
        out
    }

    pub fn ingress(&self) -> Option<(&'static str, u16)> {
        let published: Vec<(u16, u16)> = self
            .lab
            .services
            .get("proxy")?
            .ports
            .iter()
            .filter_map(|p| published_port(p))
            .collect();

        ingress_endpoint(&published)
    }
}

/// The reachable-from-here publishes, as (host, container) pairs.
///
/// A gateway-bound publish is for pods and containers inside the lab, and
/// verify runs on this machine.
fn published_port(mapping: &str) -> Option<(u16, u16)> {
    let m = crate::domain::port_mapping::PortMapping::parse(mapping)?;
    m.is_host_reachable().then_some((m.host, m.container))
}

pub fn ingress_endpoint(published: &[(u16, u16)]) -> Option<(&'static str, u16)> {
    let on_container_port = |want: u16| published.iter().find(|(_, c)| *c == want).map(|(h, _)| *h);

    on_container_port(443)
        .map(|host| ("https", host))
        .or_else(|| on_container_port(80).map(|host| ("http", host)))
}

pub async fn run(ctx: &VerifyContext<'_>, only: Option<&str>) -> Vec<Diagnostic> {
    let wanted = |name: &str| only.is_none_or(|o| o == name);

    let mut diags = Vec::new();
    if wanted("clusters") {
        diags.extend(checks::clusters::run(ctx));
    }
    if wanted("services") {
        diags.extend(checks::services::run(ctx));
    }
    if wanted("rollouts") {
        diags.extend(checks::rollouts::run(ctx));
    }
    if wanted("endpoints") {
        diags.extend(checks::endpoints::run(ctx).await);
    }
    if wanted("certificates") {
        diags.extend(checks::certificates::run(ctx));
    }
    if wanted("chainsaw")
        && let Some(package) = ctx.package
    {
        diags.extend(checks::chainsaw::run(ctx, package));
    }
    diags
}

#[derive(Debug, Serialize)]
pub struct JsonDiagnostic {
    pub severity: &'static str,
    pub check: &'static str,
    pub cluster: String,
    pub resource: String,
    pub message: String,
}

pub fn as_json(diagnostics: &[Diagnostic]) -> Vec<JsonDiagnostic> {
    diagnostics
        .iter()
        .map(|d| JsonDiagnostic {
            severity: match d.severity {
                Severity::Error => "error",
                Severity::Warning => "warning",
            },
            check: d.check,
            cluster: d.cluster.clone(),
            resource: d.resource.clone(),
            message: d.message.clone(),
        })
        .collect()
}

pub fn diag(
    severity: Severity,
    check: &'static str,
    cluster: &str,
    resource: &str,
    message: String,
) -> Diagnostic {
    Diagnostic {
        severity,
        check,
        cluster: cluster.to_string(),
        file: std::path::PathBuf::new(),
        resource: resource.to_string(),
        message,
    }
}

#[cfg(test)]
mod tests {

    /// The ingress publishes on loopback and on the lab's own gateway, so a
    /// mapping carries an address. Reading the address as the host port made
    /// verify say a working lab published no ingress at all.
    #[test]
    fn the_ingress_port_is_found_whatever_it_is_bound_to() {
        assert_eq!(super::published_port("127.0.0.1:8080:80"), Some((8080, 80)));
        assert_eq!(super::published_port("8080:80"), Some((8080, 80)));
        assert_eq!(
            super::published_port("127.0.0.1:9443:443"),
            Some((9443, 443))
        );
        assert_eq!(super::published_port("172.20.0.1:80:80"), None);
    }
    use super::*;

    use serde_json::{Value, json};

    fn merge(base: &mut Value, over: Value) {
        match (base, over) {
            (Value::Object(b), Value::Object(o)) => {
                for (k, v) in o {
                    merge(b.entry(k).or_insert(Value::Null), v);
                }
            }
            (b, o) => *b = o,
        }
    }

    fn base_lab() -> Value {
        json!({
            "labName": "l",
            "clusterNames": [],
            "clusters": {},
            "routedHosts": {},
            "network": { "name": "l", "dockerSubnet": "172.20.0.0/16" },
            "dnsInfo": null,
            "registryPort": null,
            "registryUpstreams": [],
            "labOwnedRegistries": [],
            "opsToolPath": null,
            "cd": { "bootstrap": "kubectl-ssa", "git": {} },
            "secrets": { "envFile": null, "stores": {}, "managed": {}, "hostProjections": [] },
            "deploymentPlan": [],
            "teardownPlan": [],
            "services": {},
            "destroy": { "rescueHints": {} },
            "verify": {},
        })
    }

    fn base_cluster(name: &str) -> Value {
        json!({
            "clusterHandle": {
                "name": name,
                "instanceName": format!("l-{name}"),
                "context": format!("k3d-{name}"),
                "kubernetes": { "distribution": "k3s", "version": "1.31", "controlPlanes": 1, "workers": 0 },
                "network": { "podSubnet": "10.244.0.0/16", "serviceSubnet": "10.96.0.0/12" },
            },
            "provisioning": {
                "config": {
                    "k3d": { "clusterName": name, "image": null, "network": null,
                             "noTraefik": true, "noServiceLB": false, "noFlannel": false, "noLocalStorage": false,
                             "ports": [], "extraApiServerArgs": [], "extraVolumes": [],
                             "autoDeployManifests": [] },
                },
                "hooks": [],
                "wait": "10m",
            },
            "content": {
                "tree": "/dev/null",
                "namespaces": [],
                "waves": [],
                "exposedHosts": [],
                "projections": {},
            },
            "delivery": { "strategy": "kapp", "waitTimeout": "10m" },
        })
    }

    fn with(overrides: Value) -> (LabSpec, VerifyConfig) {
        let mut lab = base_lab();
        merge(&mut lab, overrides);
        if let Some(clusters) = lab["clusters"].as_object_mut() {
            for (name, cluster) in clusters.iter_mut() {
                let mut full = base_cluster(name);
                merge(&mut full, cluster.clone());
                *cluster = full;
            }
        }
        (
            serde_json::from_value(lab).expect("test lab spec parses"),
            VerifyConfig::default(),
        )
    }

    #[test]
    fn exposed_hosts_are_collected_across_clusters_and_deduped() {
        let (lab, config) = with(json!({
            "clusterNames": ["mgmt", "apps"],
            "routedHosts": { "mgmt": ["a.test", "b.test"], "apps": ["b.test"] },
            "clusters": {
                "mgmt": { "content": { "exposedHosts": [
                    { "host": "b.test", "tier": "public", "namespace": "n", "bundle": "x" },
                    { "host": "a.test", "tier": "internal", "namespace": "n", "bundle": "y" },
                ]}},
                "apps": { "content": { "exposedHosts": [
                    { "host": "b.test", "tier": "public", "namespace": "n", "bundle": "z" },
                ]}},
            },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        let hosts: Vec<String> = ctx
            .exposed_hosts()
            .into_iter()
            .map(|(_, h)| h.host)
            .collect();
        assert_eq!(hosts, vec!["a.test", "b.test"]);
    }

    /// The filter is per hostname, not per cluster.
    ///
    /// A fronted cluster can still render a route for a hostname nothing in
    /// it claimed — the ingress has no `use_backend` for that name, so the
    /// probe would get HAProxy's default 503 and blame the workload.
    /// `checks.lab-routed-hosts-are-claimed` refuses the arrangement on the
    /// Nix side; this is what happens to a document that has it anyway.
    #[test]
    fn an_unclaimed_host_in_a_fronted_cluster_is_not_probed() {
        let (lab, config) = with(json!({
            "clusterNames": ["app"],
            "routedHosts": { "app": ["claimed.test"] },
            "clusters": {
                "app": { "content": { "exposedHosts": [
                    { "host": "claimed.test", "tier": "public", "namespace": "n", "bundle": "x" },
                    { "host": "stray.test", "tier": "public", "namespace": "n", "bundle": "y" },
                ]}},
            },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        assert_eq!(
            ctx.exposed_hosts()
                .into_iter()
                .map(|(_, h)| h.host)
                .collect::<Vec<_>>(),
            vec!["claimed.test"]
        );
        assert_eq!(
            ctx.unreachable_hosts()
                .into_iter()
                .map(|(_, h)| h.host)
                .collect::<Vec<_>>(),
            vec!["stray.test"]
        );
    }

    /// A cluster the lab does not front is not probed through the lab.
    ///
    /// `verify` resolves every routed host to the lab's ingress on loopback,
    /// which is right exactly for the names the ingress answers for. For one
    /// it does not the probe would dial HAProxy for a name HAProxy has no
    /// backend for, get its default 503, and report the cluster as broken
    /// when nothing about it is.
    ///
    /// `cloud` is absent from the host map rather than present with a mode
    /// saying to skip it: the map is what the ingress was built from, so
    /// there is no second statement to disagree with it.
    #[test]
    fn a_self_edge_clusters_hosts_are_not_probed_through_the_lab() {
        let (lab, config) = with(json!({
            "clusterNames": ["local", "cloud"],
            "routedHosts": { "local": ["here.test"] },
            "clusters": {
                "local": { "content": { "exposedHosts": [
                    { "host": "here.test", "tier": "public", "namespace": "n", "bundle": "x" },
                ]}},
                "cloud": { "content": { "exposedHosts": [
                    { "host": "there.test", "tier": "public", "namespace": "n", "bundle": "y" },
                ]}},
            },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        let hosts: Vec<String> = ctx
            .exposed_hosts()
            .into_iter()
            .map(|(_, h)| h.host)
            .collect();
        assert_eq!(hosts, vec!["here.test"]);

        let unreachable: Vec<String> = ctx
            .unreachable_hosts()
            .into_iter()
            .map(|(_, h)| h.host)
            .collect();
        assert_eq!(unreachable, vec!["there.test"]);
    }

    #[test]
    fn a_lab_with_no_routes_has_nothing_to_probe() {
        let (lab, config) = with(json!({
            "clusterNames": ["app"],
            "clusters": { "app": {} },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        assert!(ctx.exposed_hosts().is_empty());
    }

    #[test]
    fn the_ingress_follows_the_proxy_ports() {
        let plain = with(json!({
            "services": { "proxy": {
                "container": "catallaxy-proxy", "description": "proxy", "image": "haproxy",
                "ports": ["80:80"], "volumes": {},
            } },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &plain.0,
            config: &plain.1,
            package: None,
        };
        assert_eq!(ctx.ingress(), Some(("http", 80)));

        let tls = with(json!({
            "services": { "proxy": {
                "container": "catallaxy-proxy", "description": "proxy", "image": "haproxy",
                "ports": ["80:80", "443:443"], "volumes": {},
            } },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &tls.0,
            config: &tls.1,
            package: None,
        };
        assert_eq!(ctx.ingress(), Some(("https", 443)));
    }

    #[test]
    fn a_lab_with_no_proxy_has_no_ingress_to_probe_through() {
        let (lab, config) = with(json!({}));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        assert_eq!(ctx.ingress(), None);
    }

    #[test]
    fn namespaces_come_from_the_clusters_own_content() {
        let (lab, config) = with(json!({
            "clusterNames": ["app"],
            "clusters": { "app": { "content": { "namespaces": ["podinfo", "gateway"] } } },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        assert_eq!(
            ctx.namespaces_for("app").to_vec(),
            vec!["podinfo", "gateway"]
        );
        assert!(ctx.namespaces_for("nonexistent").is_empty());
    }

    #[test]
    fn an_empty_context_is_no_context_at_all() {
        let (lab, config) = with(json!({
            "clusterNames": ["app", "obs"],
            "clusters": {
                "app": { "clusterHandle": { "context": "" } },
                "obs": { "clusterHandle": { "context": "k3d-obs" } },
            },
        }));
        let ctx = VerifyContext {
            lab_name: "l",
            lab: &lab,
            config: &config,
            package: None,
        };
        assert_eq!(ctx.context_for("app"), None);
        assert_eq!(ctx.context_for("obs"), Some("k3d-obs"));
    }

    #[test]
    fn the_endpoint_policy_defaults_to_probing() {
        let config: VerifyConfig = serde_json::from_value(serde_json::json!({})).unwrap();
        assert!(config.endpoints.enable);
        assert!(config.endpoints.accept_statuses.is_empty());
        assert!(config.checks.is_empty());
    }
}

#[cfg(test)]
mod probe_path_tests {
    use crate::verify::ExposedHost;

    fn host_with(paths: Vec<&str>) -> ExposedHost {
        ExposedHost {
            host: "h.test".to_string(),
            tier: "public".to_string(),
            namespace: "n".to_string(),
            bundle: "b".to_string(),
            paths: paths.into_iter().map(String::from).collect(),
        }
    }

    #[test]
    fn a_route_that_matches_everything_is_probed_at_the_root() {
        assert_eq!(host_with(vec![]).probe_path(), "/");
    }

    #[test]
    fn a_path_scoped_route_is_probed_where_it_routes() {
        assert_eq!(
            host_with(vec!["/api/v1/write"]).probe_path(),
            "/api/v1/write",
            "probing / would ask for a path the route is right to refuse"
        );
    }

    #[test]
    fn the_first_path_is_the_one_probed() {
        assert_eq!(host_with(vec!["/a", "/b"]).probe_path(), "/a");
    }
}

#[cfg(test)]
mod endpoint_status_tests {
    use crate::verify::checks::endpoints::answered;

    #[test]
    fn a_route_that_resolved_counts_as_answered() {
        for status in [200, 204, 301, 302, 399] {
            assert!(answered(status), "{status} should count as an answer");
        }
    }

    #[test]
    fn declining_the_request_still_proves_the_route() {
        assert!(answered(401));
        assert!(answered(403));
    }

    #[test]
    fn declining_the_method_still_proves_the_route() {
        assert!(
            answered(405),
            "a write-only endpoint answers GET with 405, and only the workload can"
        );
    }

    #[test]
    fn a_404_is_the_gateway_saying_no_route_matched() {
        assert!(
            !answered(404),
            "a 404 is exactly the routing failure this check exists to catch"
        );
    }

    #[test]
    fn a_server_error_is_not_an_answer() {
        for status in [500, 502, 503] {
            assert!(!answered(status), "{status} must fail");
        }
    }
}

#[cfg(test)]
mod ingress_endpoint_tests {
    use super::ingress_endpoint;

    #[test]
    fn the_default_ports_resolve_as_they_always_did() {
        assert_eq!(ingress_endpoint(&[(80, 80)]), Some(("http", 80)));
        assert_eq!(
            ingress_endpoint(&[(80, 80), (443, 443)]),
            Some(("https", 443))
        );
    }

    #[test]
    fn a_remapped_host_port_is_still_the_ingress() {
        assert_eq!(
            ingress_endpoint(&[(8080, 80)]),
            Some(("http", 8080)),
            "a lab that moves off port 80 to share a machine still has an ingress"
        );
        assert_eq!(
            ingress_endpoint(&[(8080, 80), (8443, 443)]),
            Some(("https", 8443))
        );
    }

    #[test]
    fn tls_wins_over_plaintext_whatever_the_host_port() {
        assert_eq!(
            ingress_endpoint(&[(9443, 443), (9080, 80)]),
            Some(("https", 9443))
        );
    }

    #[test]
    fn a_proxy_publishing_neither_has_no_ingress() {
        assert_eq!(ingress_endpoint(&[]), None);
        assert_eq!(ingress_endpoint(&[(5353, 53)]), None);
    }
}
