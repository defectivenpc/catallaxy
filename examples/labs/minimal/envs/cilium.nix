# The minimal lab with Cilium instead of flannel.
#
# Exists to boot a CNI, which is the one thing rendering cannot check: the
# bootstrap manifest is applied by the provisioner before any node is Ready,
# and nothing short of starting one tells you whether that happens.
#
# It also gives the network-policy work a cluster that enforces a
# NetworkPolicy. k3s ships flannel, which implements none — a policy applied
# to `minimal.local` is admitted, stored, and enforced by nothing.
#
# Two lines, where this used to be a `mkForce` on the provisioner carrying
# `disableFlannel` and a hand-templated bootstrap manifest, plus the `cilium`
# floe beside it. Both halves are the floe's now and travel through
# `CNI_BOOTSTRAP`, so a cluster with no network and a cluster with two are
# states nobody can write.
{
  lab,
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ../clusters.nix { inherit catallaxy floes lib; };
in
lab {
  name = "minimal.cilium";

  cluster = clusters.appWithCilium { };

  # Presence wires nothing: a cluster that contains Cilium is not thereby a
  # cluster whose provisioner starts with no network at all. This is that
  # third decision, said once.
  defaults.CNI_BOOTSTRAP = "app";
}
