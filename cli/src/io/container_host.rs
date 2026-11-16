//! Turning a lab's container host into a daemon `cata` can talk to.

use anyhow::Result;
use console::style;

use crate::config::Colima;
use crate::domain::container_host::{ColimaHost, ContainerHost};
use crate::io;
use crate::io::docker::Docker;

/// The Colima profile a host runs on, if it runs on one here.
///
/// A local host on macOS is Colima's `catallaxy` profile, because that is
/// where an operator on a Mac runs docker. `CATA_COLIMA_DISABLE` takes every
/// Colima host back to the environment's own socket, for Docker Desktop.
fn colima_profile<'a>(colima: &Colima, host: &'a ContainerHost) -> Option<&'a str> {
    match host {
        _ if !colima.enable => None,
        ContainerHost::Colima(ColimaHost { profile }) => Some(profile),
        ContainerHost::Local(_) if io::colima::is_macos() => Some("catallaxy"),
        ContainerHost::Local(_) | ContainerHost::Ssh(_) => None,
    }
}

/// The `DOCKER_HOST` a host is reached through, or `None` for "whatever the
/// environment resolves to". Starts nothing: a VM that is down stays down,
/// and the daemon simply does not answer.
pub fn endpoint(colima: &Colima, host: &ContainerHost) -> Option<String> {
    colima_profile(colima, host)
        .map(io::colima::docker_socket)
        .or_else(|| host.ssh_endpoint())
}

/// The daemon a host is reached through, as [`endpoint`] finds it.
pub fn docker_for(colima: &Colima, host: &ContainerHost) -> Docker {
    Docker::at(endpoint(colima, host))
}

/// The docker on the operator machine, as a local host resolves there.
///
/// For the commands that look at what is running without a lab to ask:
/// `lab list` and `lab cleanup` read the operator machine, so a lab on a
/// remote host is not theirs to find.
pub fn operator_docker() -> Docker {
    docker_for(&Colima::from_env(), &ContainerHost::default())
}

/// Bring a host's engine up when it is one `cata` runs, and say where it is.
///
/// A Colima profile that is not running is started, sized by the operator's
/// `CATA_COLIMA_*`: one profile serves every lab, so its size is not any one
/// lab's to say. Call it before probing the daemon and not after, because a
/// reachability check that runs first can only ever refuse.
///
/// # Errors
///
/// If Colima cannot be started.
pub fn ensure_up(colima: &Colima, host: &ContainerHost) -> Result<Option<String>> {
    if let Some(profile) = colima_profile(colima, host) {
        if io::colima::profile_running(profile) {
            println!(
                "{} Colima VM already running (profile: {profile})",
                style(">>>").green(),
            );
        } else {
            io::colima::start(profile, colima.cpu, colima.memory, colima.disk)?;
        }
    }
    Ok(endpoint(colima, host))
}
