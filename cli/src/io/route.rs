use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};

pub fn gateway_for(destination: &str) -> Option<String> {
    let out = Command::new("route")
        .args(["-n", "get", destination])
        .output()
        .ok()?;
    parse_gateway(&String::from_utf8_lossy(&out.stdout))
}

/// The gateway of a route installed *for this destination*, or `None`.
///
/// `route -n get` answers with whatever route would carry the packet, which
/// is the default route when nothing specific is installed — so asking about
/// an absent subnet reports the machine's own uplink gateway, and a caller
/// that only read `gateway:` concluded a route was there. The destination it
/// echoes back is what tells the two apart.
///
/// Reading this is unprivileged, which is the point: it decides whether a
/// change needing `sudo` is required before asking for a password.
pub fn gateway_for_exactly(destination: &str) -> Option<String> {
    let out = Command::new("route")
        .args(["-n", "get", destination])
        .output()
        .ok()?;
    let answer = String::from_utf8_lossy(&out.stdout);
    (parse_destination(&answer).as_deref() == Some(destination))
        .then(|| parse_gateway(&answer))
        .flatten()
}

fn field(route_output: &str, name: &str) -> Option<String> {
    route_output
        .lines()
        .find(|l| l.trim().starts_with(name))
        .map(|l| l.trim().trim_start_matches(name).trim().to_string())
}

pub fn parse_gateway(route_output: &str) -> Option<String> {
    field(route_output, "gateway:")
}

pub fn parse_destination(route_output: &str) -> Option<String> {
    field(route_output, "destination:")
}

/// # Errors
///
/// Only if `sudo` cannot be spawned. A route that is not there is a non-zero
/// `ExitStatus`, and both streams are discarded, so removing a route that was
/// never added is quiet.
pub fn delete(subnet: &str) -> std::io::Result<std::process::ExitStatus> {
    Command::new("sudo")
        .args(["route", "-n", "delete", "-net", subnet])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
}

/// # Errors
///
/// If `sudo` cannot be spawned, or exits non-zero because the operator
/// declined the prompt or the route already exists.
pub fn add(subnet: &str, gateway: &str) -> Result<()> {
    let status = Command::new("sudo")
        .args(["route", "-n", "add", "-net", subnet, gateway])
        .status()
        .context("Failed to run sudo route add")?;
    if !status.success() {
        bail!("Failed to add route for {subnet} via {gateway}");
    }
    Ok(())
}

pub fn arp_table() -> Option<String> {
    let out = Command::new("arp")
        .args(["-an"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&out.stdout).to_string())
}

pub fn bridge_address(arp_output: &str, interface: &str) -> Option<String> {
    arp_output.lines().find_map(|line| {
        if !line.contains(interface) {
            return None;
        }
        let start = line.find('(')?;
        let end = line.find(')')?;
        let ip = &line[start + 1..end];
        (!ip.is_empty()).then(|| ip.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_gateway_is_read_off_its_own_indented_line() {
        let out = "   route to: 172.19.0.0\ndestination: 172.19.0.0\n   gateway: 192.168.106.2\n";
        assert_eq!(parse_gateway(out), Some("192.168.106.2".to_string()));
    }

    #[test]
    fn a_destination_with_no_route_has_no_gateway() {
        assert_eq!(
            parse_gateway("route: writing to routing socket: not in table"),
            None
        );
    }

    /// What macOS actually answers for a subnet nobody routed: the default
    /// route, carrying the uplink's gateway. Reading `gateway:` alone takes
    /// this for a route to the subnet and escalates to `sudo` to remove
    /// something that was never added.
    #[test]
    fn the_default_route_is_not_a_route_for_the_subnet_asked_about() {
        let answer = "   route to: 172.16.32.0\n\
                      destination: default\n\
                             mask: default\n\
                          gateway: 10.120.0.1\n\
                        interface: en0\n";
        assert_eq!(parse_destination(answer).as_deref(), Some("default"));
        assert_eq!(parse_gateway(answer).as_deref(), Some("10.120.0.1"));
    }

    #[test]
    fn a_route_installed_for_the_subnet_echoes_that_destination_back() {
        let answer = "   route to: 172.16.32.0\n\
                      destination: 172.16.32.0\n\
                          gateway: 192.168.64.2\n";
        assert_eq!(parse_destination(answer).as_deref(), Some("172.16.32.0"));
    }

    #[test]
    fn the_bridge_address_comes_from_the_arp_entry_naming_that_interface() {
        let arp = "? (192.168.64.1) at 0:0:0:0:0:0 on bridge100 ifscope permanent [ethernet]\n\
                   ? (10.0.0.1) at 1:2:3:4:5:6 on en0 ifscope [ethernet]\n";
        assert_eq!(
            bridge_address(arp, "bridge100"),
            Some("192.168.64.1".to_string())
        );
    }

    #[test]
    fn an_arp_table_without_that_interface_yields_nothing() {
        assert_eq!(
            bridge_address("? (10.0.0.1) at 1:2:3:4:5:6 on en0\n", "bridge100"),
            None
        );
    }
}
