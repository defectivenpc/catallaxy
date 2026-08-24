//! What a lab declares about verifying itself.
//!
//! Lives here rather than in `crate::verify` because `LabSpec` carries it:
//! the field was a `serde_json::Value` for want of somewhere to put the type,
//! which made `lab verify` parse the evaluated lab twice — once untyped to
//! reach `raw["verify"]`, and once into `LabSpec`.

use std::collections::BTreeMap;

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct VerifyConfig {
    #[serde(default)]
    pub checks: BTreeMap<String, DeclaredCheck>,
    #[serde(default)]
    pub endpoints: EndpointPolicy,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeclaredCheck {
    pub description: String,
    pub severity: String,
    pub scope: String,
    pub command: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EndpointPolicy {
    pub enable: bool,
    #[serde(default)]
    pub accept_statuses: Vec<u16>,
}

impl Default for EndpointPolicy {
    /// Endpoints are checked unless a lab says otherwise, and every status is
    /// acceptable unless it lists some.
    fn default() -> Self {
        Self {
            enable: true,
            accept_statuses: Vec::new(),
        }
    }
}
