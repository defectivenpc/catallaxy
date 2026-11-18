//! A container host reached over SSH: the files its mounts read, and the
//! tunnel its loopback ports are dialled through.
//!
//! Everything here takes the SSH target (`user@address`) and nothing about a
//! lab's layout, so a lab on a remote host is the same lab with these two
//! adapters in front of it.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result, bail};

/// Where a remote host keeps copies of the files mounted into its
/// containers, relative to the remote user's home.
const MOUNTS: &str = ".local/share/catallaxy/mounts";

/// The remote user's home, asked once per call site.
fn remote_home(target: &str) -> Result<String> {
    let out = Command::new("ssh")
        .args(["-o", "BatchMode=yes", target, "printf %s \"$HOME\""])
        .output()
        .with_context(|| format!("failed to run ssh to {target}"))?;
    if !out.status.success() {
        bail!(
            "ssh {target} failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// The path a local file or directory is mounted from on a remote host.
///
/// Its own absolute path under the remote mounts root, so two files never
/// collide and nothing has to know which lab or service a file belongs to.
///
/// ```
/// use cata::io::remote::mounted_at;
/// assert_eq!(
///     mounted_at("/home/ops", "/nix/store/abc-policy.yaml"),
///     "/home/ops/.local/share/catallaxy/mounts/nix/store/abc-policy.yaml",
/// );
/// ```
pub fn mounted_at(remote_home: &str, local: &str) -> String {
    format!("{remote_home}/{MOUNTS}/{}", local.trim_start_matches('/'))
}

/// Copy a local file or directory to the remote host and say where it is.
///
/// Symlinks are copied as what they point at, because a store path's
/// symlink has nothing to point at on the other side; a directory is made
/// to match, so a file removed locally is removed there too.
///
/// # Errors
///
/// If ssh or rsync cannot reach the host, or the copy fails.
pub fn place(target: &str, local: &str) -> Result<String> {
    let home = remote_home(target)?;
    let root = format!("{home}/{MOUNTS}");
    let source = if Path::new(local).is_dir() {
        format!("{}/", local.trim_end_matches('/'))
    } else {
        local.to_string()
    };
    let status = Command::new("rsync")
        .args([
            "-aLR",
            "--delete",
            "--rsync-path",
            &format!("mkdir -p {root} && rsync"),
            &source,
            &format!("{target}:{root}/"),
        ])
        .stdout(Stdio::null())
        .status()
        .context("failed to run rsync")?;
    if !status.success() {
        bail!("could not copy {local} to {target}");
    }
    Ok(mounted_at(&home, local))
}

/// The control socket of this lab's tunnel to a host.
fn socket(state_dir: &Path, target: &str) -> PathBuf {
    let host = target.rsplit('@').next().unwrap_or(target);
    state_dir.join(format!("tunnel-{host}.sock"))
}

fn control(state_dir: &Path, target: &str, args: &[&str]) -> Command {
    let mut cmd = Command::new("ssh");
    cmd.arg("-S")
        .arg(socket(state_dir, target))
        .args(args)
        .arg(target);
    cmd
}

/// Make sure this lab's tunnel to a host is up, and forward a port through it.
///
/// One SSH connection per lab and host, held open by a control socket in
/// the lab's state directory; each port is added to it as it is needed. The
/// same number at both ends, so a kubeconfig or a URL that says
/// `127.0.0.1:<port>` means the same thing on the operator machine as on
/// the host.
///
/// # Errors
///
/// If the connection cannot be made, or the port cannot be forwarded,
/// usually because something on the operator machine already holds it.
pub fn forward(state_dir: &Path, target: &str, port: u16) -> Result<()> {
    std::fs::create_dir_all(state_dir)?;
    let up = control(state_dir, target, &["-O", "check"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success());
    if !up {
        let status = control(
            state_dir,
            target,
            &[
                "-fNM",
                "-o",
                "BatchMode=yes",
                "-o",
                "ControlPersist=yes",
                "-o",
                "ExitOnForwardFailure=yes",
            ],
        )
        .status()
        .context("failed to run ssh")?;
        if !status.success() {
            bail!("could not open a tunnel to {target}");
        }
    }
    let spec = format!("127.0.0.1:{port}:127.0.0.1:{port}");
    let out = control(state_dir, target, &["-O", "forward", "-L", &spec])
        .output()
        .context("failed to run ssh")?;
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() && !stderr.contains("already") {
        bail!(
            "could not forward port {port} to {target}: {}",
            stderr.trim()
        );
    }
    Ok(())
}

/// Close this lab's tunnel to a host, if it has one.
pub fn close(state_dir: &Path, target: &str) {
    let _ = control(state_dir, target, &["-O", "exit"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// A port free on the operator machine's loopback, for a remote service
/// to publish on so the tunnel can carry it under the same number.
///
/// # Errors
///
/// If no port can be bound.
pub fn free_port() -> Result<u16> {
    Ok(std::net::TcpListener::bind("127.0.0.1:0")?
        .local_addr()?
        .port())
}
