# homelab, with a mesh control plane on `core` and both clusters on the mesh.
#
# This is the lab that exercises all three scopes at once, which is what makes
# it worth having beside `homelab.local`:
#
# **Chart.** `netbird-operator` wraps a helm chart, and nothing outside that
# floe names a chart value. Both clusters instantiate the same floe with the
# same chart and differ in exactly one input.
#
# **Cluster.** Each cluster's operator promises `MESH_OPERATOR`, every field of
# which is link-local — a controller here, CRDs here. Neither cluster can offer
# it to the other and neither should: an operator in `core` does not reconcile
# a CR applied in `obs`.
#
# **Lab.** `core` exposes one provision, `netbird/mesh`. `obs` runs no control
# plane, so its operator's `MESH_NETWORK` hole finds nothing local and resolves
# from the lab scope — where `managementUrl` reads and `managementInternalUrl`
# is a throw naming the field.
#
# netbird lives on `core` beside kanidm because it has to: it has no local
# accounts at all, so a netbird without an issuer in the same cluster is one
# nobody — including its own operator — can log into.
#
# What this proves that `every-floe` cannot: four workloads that fail apart
# rather than together actually come up. Management renders its config from a
# template with two credentials substituted by an init container, and if that
# substitution does not happen the server starts anyway and refuses every peer.
# `cata --flake .#homelab.mesh lab ops -- mesh core-netbird-config` asks the
# running server whether any placeholder survived.
#
# ## The token, and why it is not a signature
#
# The operator spends a netbird personal access token. `core` mints it and
# promises where it landed (`MESH_ADMIN`), which `core`'s own operator resolves
# with nothing said here. `obs` cannot resolve that promise — a reference to a
# Secret in another cluster's namespace means nothing, and `link` refuses to
# let it try — so the *value* crosses the way every value does, through
# the lab's runtime store, and `obs`'s operator is told where the subscription
# put it.
#
# Two mechanisms, and the split is not an accident: a signature carries
# configuration and a subscription carries content. Threading the token through
# a signature would put secret material in a rendered manifest, which is the
# one thing no floe may do.
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
  name = "homelab.mesh";

  units = {
    # Two stores: one a human authored, one the lab writes into at runtime. The
    # Vault credential is minted by `cata secrets generate` and lands in the
    # first; everything the clusters publish goes through the second.
    #
    # Both are units of the lab's link, so what reads them resolves them. With
    # two in the link nothing resolves by default and every reader says which
    # it means, which is the ambiguity being real rather than ceremony.
    authored = floes.lab-secret-store { backend = "sops"; };

    runtime = floes.lab-secret-store {
      backend = "vault";
      inherit (clusters) vaultServer;
    };

    vault-credential =
      (floes.lab-authored-secret {
        keys.token.generator = "hex";
        keys.token.length = 32;
      }).bind
        { labStore = "authored"; };
  };

  # Both clusters are different from `homelab.local`'s rather than those with a
  # flag: `core` runs the mesh and publishes its PAT, `obs` joins the mesh and
  # subscribes to the PAT. The crossing is `core`'s export and `obs` resolving
  # against it, which is the same mechanism one cluster provisioning another
  # uses.
  #
  # `runtime`, because that is the one a cluster pushes into. `secret` needs no
  # binding: there is one `LAB_SECRET` in the link.
  core = (clusters.coreWithMesh { }).bind { labStore = "runtime"; };
  obs = (clusters.obsWithMesh { }).bind { labStore = "runtime"; };
}
