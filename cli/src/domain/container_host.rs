use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// The docker engine a cluster or a host service runs on, as the lab names it.
///
/// Which engine, never its socket: Colima's lives under the operator's home
/// and exists only once the VM is up, so `cata` turns this into `DOCKER_HOST`
/// when it runs. Externally tagged, like the provisioner union, so
/// `{"ssh": {"address": "10.0.0.11", "user": null}}` is a host and a stray
/// field beside the tag cannot contradict it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum ContainerHost {
    Local(LocalHost),
    Colima(ColimaHost),
    Ssh(SshHost),
}

/// The docker on the operator's machine, whatever runs it there.
///
/// Which VM that is, if any, is the operator's to say rather than the lab's:
/// on macOS `cata` resolves it to Colima's `catallaxy` profile unless
/// `CATA_COLIMA_DISABLE` is set, and everywhere else to the environment's
/// own socket.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
pub struct LocalHost {}

/// A Colima profile on the operator's machine.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ColimaHost {
    pub profile: String,
}

/// A remote docker engine reached over SSH.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct SshHost {
    pub address: String,
    pub user: Option<String>,
}

impl Default for ContainerHost {
    fn default() -> Self {
        Self::Local(LocalHost {})
    }
}

impl ContainerHost {
    /// The `DOCKER_HOST` an SSH host is reached through, or `None` for an
    /// engine on the operator's machine, whose socket is `cata`'s to find.
    ///
    /// ```
    /// use cata::domain::container_host::{ContainerHost, SshHost};
    /// let box1 = ContainerHost::Ssh(SshHost { address: "10.0.0.11".into(), user: Some("ops".into()) });
    /// assert_eq!(box1.ssh_endpoint().as_deref(), Some("ssh://ops@10.0.0.11"));
    /// ```
    pub fn ssh_endpoint(&self) -> Option<String> {
        match self {
            Self::Ssh(SshHost { address, user }) => Some(match user {
                Some(u) => format!("ssh://{u}@{address}"),
                None => format!("ssh://{address}"),
            }),
            Self::Local(_) | Self::Colima(_) => None,
        }
    }
}
