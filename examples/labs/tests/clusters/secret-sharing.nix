# Two clusters, one of which mints material the other reads.
#
# `core` publishes its CA into a Vault-backed store and *exports* the
# publication; `obs` subscribes to it. That export is the mechanism — one
# cluster names what another may read, in the signature the boundary allows —
# and it is the same mechanism a cluster provisioning another uses, which is
# the collapse ADR 0002 predicted.
#
# `provides = [ "publish-ca/publication" ]` plus a table of crossable
# signatures is what this replaces: the boundary says both now.
{
  catallaxy,
  floes,
  lib,
  vaultServer,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;

  # Every cluster here reads the same store, and the token that opens it is
  # lab-held material projected into the namespace external-secrets runs in.
  shared = {
    kapp = floes.kapp { };

    vault-token = floes.secret-projection {
      secret = "vault-token";
      namespace = "external-secrets";
      keys.token.from = "token";
    };

    external-secrets = floes.external-secrets { };

    store = floes.secret-store { server = vaultServer; };
  };

  # What `shared` reads of the lab, so every cluster built from it declares
  # the same two holes: the runtime store its `secret-store` backs, and the
  # authored secret the projection fills from. The lab has two stores, so it
  # says which the first means.
  sharedRequires = {
    labStore = sigs.LAB_SECRET_STORE;
    secret = sigs.LAB_SECRET;
  };

  base =
    {
      name,
      extraUnits,
      extraRequires ? { },
      extraProvides ? { },
      extraExports ? { },
    }:
    mkClusterFloe {
      name = "secret-sharing-${name}";
      summary = "A Vault-backed secret store and what this cluster does with it.";

      requires = {
        claim = sigs.KUBERNETES_CLUSTER;
      }
      // sharedRequires
      // extraRequires;

      provides = {
        delivery = sigs.DELIVERY_POLICY;
      }
      // extraProvides;

      exports = {
        delivery = "kapp/delivery";
      }
      // extraExports;

      units = _: shared // extraUnits;
    };
in
{
  core = base {
    name = "core";

    extraUnits = {
      cert-manager = floes.cert-manager { };

      publish-ca = floes.secret-publication {
        namespace = "cert-manager";
        secret = "lab-ca-ca-secret";
        key = "secret-sharing/core/lab-ca";
      };
    };

    extraProvides.publication = sigs.PUBLISHED_SECRET;
    extraExports.publication = "publish-ca/publication";
  };

  obs = base {
    name = "obs";

    extraUnits.subscribe-ca = floes.secret-subscription {
      namespace = "default";
      secret = "core-lab-ca";
      labels."catallaxy.io/trust" = "lab-ca";
    };

    # What `core` published. The hole is declared here and the lab fills it
    # from `core`'s export, which is the same mechanism a mesh crossing uses
    # and the same one a cluster provisioning another uses.
    extraRequires.publication = sigs.PUBLISHED_SECRET;
  };
}
