# The two clusters `homelab` stands up, and the two variants of them.
#
# `core` is the platform: identity, source control, a registry, trust,
# routing, backups. `obs` is observability: metrics, logs, traces and a
# dashboard over them. Each is a floe whose header is its interface, and each
# environment of this lab builds its own pair from the same base — which is
# what an environment is here, since `homelab.mesh` is not `homelab.local`
# with a flag but a different cluster: one on a mesh, holding a store, with a
# credential crossing to its sibling.
#
# Every one leaves its claim and the zone open. The claim because a cluster
# floe is not the thing that creates a cluster; the zone because it is a fact
# the lab holds and no cluster can derive.
{
  catallaxy,
  floes,
  lib,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;

  # What this lab's hostnames hang off. Here rather than in `lab.nix` because
  # this is the file that derives hostnames from it — `lab.nix` reads it back
  # as the default of the `zone` input, so there is one string.
  zone = "homelab.test";

  # Where the runtime store answers, for the environments that have one. A
  # hostname the lab's own ingress routes, so it is derived from the zone
  # rather than written in two files that can disagree.
  vaultServer = "https://vault.${zone}";

  # One root for the whole lab, minted on the host by `cert-generate` and
  # seeded into every cluster by `create-cluster`. Both clusters sign from it,
  # which is what lets one HAProxy terminate for both with one certificate.
  platform = floes.standard-cluster { };

  mk =
    {
      name,
      units,
      defaults ? { },
      requires ? { },
      provides ? { },
      exports ? { },
      summary,
    }:
    mkClusterFloe {
      name = "homelab-${name}";
      inherit summary defaults;

      requires = {
        cluster = sigs.KUBERNETES_CLUSTER;
        zone = sigs.DNS_ZONE;

        # Somewhere for the stateful floes in here to bind a PVC. Answered by
        # the claim, because whether a provisioner ships a default storage
        # class is the provisioner's to say.
        storageClass = sigs.STORAGE_CLASS;
      }
      // requires;

      # Where the cluster is dialled, answered by its claim. Both of this
      # lab's clusters are fronted, so both read it.
      # The lab's root, so the issuer in here signs from it rather than minting
      # a second. It was `rootFromLab = true` threaded down two levels.
      optional.labCa = sigs.LAB_CA;

      optional.edge = sigs.CLUSTER_EDGE;

      provides = {
        delivery = sigs.DELIVERY_POLICY;

        # What the lab's resolver answers for. Exported because this lab fronts
        # both of its clusters. ADR 0004.
        exposure = sigs.HOST_EXPOSURE;
      }
      // provides;

      exports = {
        delivery = "kapp/delivery";
        exposure = "platform/exposure";
      }
      // exports;

      units =
        _:
        {
          kapp = floes.kapp { };
          inherit platform;
        }
        // units;
    };

  # ---- the base pair ------------------------------------------------------

  coreUnits = {
    # kaniop runs the CRDs; kanidm is the issuer. Its clients are rendered by
    # whoever needs one — there is no list of them here and kanidm does not
    # know who its consumers are.
    kaniop = floes.kaniop { };
    kanidm = floes.kanidm { domain = "idm.${zone}"; };

    # `oidc = true` on each is the whole of the wiring. The floe resolves
    # `OIDC_PROVIDER`, renders its own client into its own namespace, and
    # reads back the credential kanidm's operator writes.
    forgejo = floes.forgejo { oidc = true; };
    harbor = floes.harbor { oidc = true; };

    # Restarts what reads a Secret or ConfigMap that changed underneath it —
    # which on this cluster is every OIDC consumer above.
    reloader = floes.reloader { };

    # velero takes its endpoint off `OBJECT_STORE` rather than from a
    # hostname written twice, so the two cannot drift.
    seaweedfs = floes.seaweedfs { };
    velero = floes.velero {
      schedules.daily = {
        schedule = "0 2 * * *";
        ttl = "168h";
      };
    };
  };

  # forgejo and harbor each render a kanidm client; saying so once is what
  # wires them, because holding both kanidm and a consumer of OIDC is not the
  # same statement as wanting them connected. Grafana on `obs` is the other
  # half of that and stays unwired — one cluster away, and silent about it by
  # declaration rather than by accident.
  coreDefaults.OIDC_PROVIDER = "kanidm";

  obsUnits = {
    # All three backends, so all three of the collector's optional holes
    # resolve and Grafana gets three datasources.
    prometheus = floes.prometheus { };
    loki = floes.loki { };
    tempo = floes.tempo { };

    otel-collector = floes.otel-collector { };

    # No `oidc`. The issuer is on `core`, and the hole resolves within a
    # cluster.
    grafana = floes.grafana { };
  };

  obsDefaults = {
    LOG_INGEST = "loki";
    METRICS_INGEST = "prometheus";
    TRACE_INGEST = "tempo";
  };
in
rec {
  inherit zone vaultServer;

  core = mk {
    name = "core";
    summary = "Identity, source control, a registry, trust, routing and backups.";
    units = coreUnits;
    defaults = coreDefaults;
  };

  obs = mk {
    name = "obs";
    summary = "Metrics, logs, traces and a dashboard over them.";
    units = obsUnits;
    defaults = obsDefaults;
  };

  # ---- `homelab.dns`: core, publishing into the lab's zone ---------------

  coreWithDns = mk {
    name = "core-dns";
    summary = "The `core` cluster, publishing records for what it routes.";
    defaults = coreDefaults;

    # The TSIG key the controller updates the zone with: a value a human
    # authored, which is the only kind of material no floe can mint for
    # itself. The projection below resolves it.
    requires.labSecret = sigs.LAB_SECRET;

    units = coreUnits // {
      # Records point at the address the zone's own server answers on, which
      # is the lab's ingress: a k3d Service reports a cluster-internal
      # LoadBalancer address nothing outside the cluster can reach, so
      # publishing what each object says would publish that.
      # No TSIG key named here. `lab-dns` tells the server one and
      # `external-dns` authenticates with one, and both floes default to the
      # same pair — so the lab was threading two values that could only ever
      # be equal, through two arguments it had to keep in step.
      external-dns = floes.external-dns {
        tsigSecretRef = "external-dns/externaldns-tsig";
      };

      externaldns-tsig = floes.secret-projection {
        secret = "externaldns-tsig";
        namespace = "external-dns";
        keys.tsig-secret.from = "tsig-secret";
      };
    };
  };

  # ---- `homelab.mesh`: both clusters on a mesh, sharing a PAT ------------

  # What both mesh clusters read of the lab: the runtime store their
  # `secret-store` backs, and the authored secret their projection fills from.
  # Two holes of two signatures, declared because `meshStoreClient` is in both
  # clusters and neither can mint either value.
  #
  # This lab has two stores, so the deployer says which this means. That is
  # the whole ceremony `.bind` exists for, and it replaced a `labStore =
  # "runtime"` string on the floe plus a `writable` flag beside it that could
  # disagree with the store's backend.
  meshRequires = {
    labStore = sigs.LAB_SECRET_STORE;
    labSecret = sigs.LAB_SECRET;
  };

  meshStoreClient = {
    vault-token = floes.secret-projection {
      secret = "vault-token";
      namespace = "external-secrets";
      keys.token.from = "token";
    };

    secret-store = floes.secret-store { server = vaultServer; };
  };

  patSecret = "netbird-api-token";
  patNamespace = "netbird";

  coreWithMesh = mk {
    name = "core-mesh";
    summary = "The `core` cluster, running the mesh and publishing its PAT.";

    defaults = coreDefaults // {
      MESH_ADMIN = "netbird";
    };

    # The mesh itself crosses, because that is the whole point of a mesh.
    # `MESH_ADMIN` does not and could not: it is a reference to a Secret in
    # this cluster, and no other cluster is this place — which is why the
    # export names the provide and not the unit.
    requires = meshRequires;

    provides = {
      mesh = sigs.MESH_NETWORK_SHARED;
      publication = sigs.PUBLISHED_SECRET;
    };

    exports = {
      mesh = "netbird/mesh";
      publication = "publish-pat/publication";
    };

    units =
      coreUnits
      // meshStoreClient
      // {
        openbao = floes.openbao { };
        netbird = floes.netbird { };
        netbird-operator = floes.netbird-operator { };

        # The one thing in the lab that needs a human: the first PAT.
        publish-pat = floes.secret-publication {
          namespace = patNamespace;
          secret = patSecret;
          key = "homelab/core/${patSecret}";
        };
      };
  };

  obsWithMesh = mk {
    name = "obs-mesh";
    summary = "The `obs` cluster, joined to the mesh `core` runs.";
    defaults = obsDefaults;

    # The mesh is `core`'s and this cluster joins it, so the hole is declared
    # here and the lab fills it from `core`'s export. In the narrowed form,
    # because that is what crossing a cluster boundary means: the full
    # `MESH_NETWORK` carries a reference to a Secret in `core`, and no other
    # cluster is that place.
    requires = meshRequires // {
      mesh = sigs.MESH_NETWORK_SHARED;

      # And the PAT itself. `subscribe-pat` reads what `core` published, so
      # the publication crosses the same way the mesh does — one cluster
      # names what another may read, and this declares that it reads it.
      publication = sigs.PUBLISHED_SECRET;
    };

    units =
      obsUnits
      // meshStoreClient
      // {
        # Told where the token is rather than minting one: the operator here
        # reconciles against the mesh `core` exports, and the PAT arrives
        # through the subscription below.
        netbird-operator = floes.netbird-operator {
          tokenSecret = "${patNamespace}/${patSecret}";
        };

        subscribe-pat = floes.secret-subscription {
          namespace = patNamespace;
          secret = patSecret;
        };
      };
  };
}
