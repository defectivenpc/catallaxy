# A container host is a hole, and a lab unit fills it

The docker engine a lab's clusters and host services run on is a value, not
an assumption. `CONTAINER_HOST` is a lab-scope signature; `local-docker`,
`colima-host` and `ssh-docker-host` are floes that provide it;
`k3d-cluster`, `talos-cluster` and every host service require it. With one
host the lab's `defaults.CONTAINER_HOST` wires it, and with several a
provisioner names the one it is placed on. Placement is wiring, the same
mechanism as `defaults.CLUSTER_PROVISIONING`, not a new subsystem.

Background and the larger design this is the first step of:
`docs/hierarchical-labs.md`.

## What it replaced

"The host" meant three things that are one machine only on a laptop: where
`cata` runs, where containers run, and where published ports are dialled
from. The second was `resolve_docker_host`, which returned Colima's socket
on macOS and nothing elsewhere, and was consulted by k3d and Talos only.
Host services spawned `docker` against whatever the operator's shell
resolved, so on a Mac whose active context was not Colima a lab's registry
and its clusters were on different daemons.

## The value is a variant, not an endpoint string

```nix
{ engine = "local"; }
{ engine = "colima"; profile = "catallaxy"; }
{ engine = "ssh"; address = "10.0.0.11"; user = "ops"; }
```

Colima's socket is under `$HOME` and only exists once the VM is started, so
neither is knowable at eval. The host names _which_ engine; `cata` turns it
into `DOCKER_HOST` when it runs, starting the VM if it has to. The address
published ports are dialled at is derived from the variant: loopback for
`local` and `colima`, the box's address for `ssh`.

## The default is the operator's machine, whatever runs docker there

A lab that names no host gets `local-docker { }`: the docker on the machine
`cata` runs on. Which engine that is stays the operator's to say, like the
VM's size: on macOS `cata` resolves it to Colima's `catallaxy` profile
unless `CATA_COLIMA_DISABLE` is set, and elsewhere to the environment's
socket. A lab that cares names `colima-host { profile = …; }` or
`ssh-docker-host`.

Choosing by platform at eval was tried first and dropped. It made every lab
document differ between Linux and macOS, so one committed snapshot could no
longer describe both, and the lab was stating a fact about the operator's
laptop that it does not depend on.

## A remote host is reached through published ports only

On an `ssh` host, ports are published on its address rather than on
`127.0.0.1`, and the operator does not route into its docker bridge. A
`talos-cluster` placed on an `ssh` host is refused at link time, because
`talosctl` dials node addresses on the bridge.

## What it did not do

**No mapping layer yet.** `provisioner =` stays in `lab.nix`. A mapping that
lifts it out is designed against two real fillers, not before them.

**Allocation stays keyed by lab.** A slot unique across every host is never
wrong, only wasteful; key by `(host, lab)` when slots run out.

**Host services are not placed individually.** They share the lab's default
host.

## Consequences

**The lab names the engine; the operator sizes the VM.** One Colima profile
serves every lab an operator runs, so its CPU, memory and disk stay
`CATA_COLIMA_{CPU,MEMORY,DISK}`: two labs asking for different sizes would
otherwise race to start the same VM. `CATA_COLIMA_DISABLE` stays too, as the
one runtime override the document does not show: an operator on Docker
Desktop sets it once, and a `colima` host resolves to the local socket.

**Every docker `cata` spawns for a lab carries the lab's host.** There is
one place that decides which daemon a lab is on, and it is the document.
