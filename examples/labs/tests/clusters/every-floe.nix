# The fixture that instantiates every floe in the catalogue.
#
# Its purpose is coverage rather than coherence: if a floe exists, it is here,
# so a change to the floe interface that breaks one shows up in a single lab.
# It renders and snapshots; it is not meant to stand up.
#
# The interface below is the honest consequence of holding everything. Three
# signatures leave this cluster — how its content is applied, the git remote
# Argo reads, and the CNI manifest its own claim has to apply before any node
# is Ready — and `defaults` names a provider for each optional hole, because
# holding both kanidm and a consumer of OIDC is not the same statement as
# wanting them wired.
{
  catallaxy,
  floes,
  lib,
  zone,
}:

let
  inherit (catallaxy) mkClusterFloe sigs;
in
{
  core = mkClusterFloe {
    name = "every-floe-core";
    summary = "Every floe in the catalogue, in one cluster, for coverage.";

    requires = {
      claim = sigs.KUBERNETES_CLUSTER;
      zone = sigs.DNS_ZONE;

      # Three stores and two secrets in this lab, so every one of these is a
      # named hole and the lab says which it means. This is the ambiguous case
      # on purpose: one `LAB_SECRET_STORE` hole and one `LAB_SECRET` hole
      # would resolve for free, and then nothing here would exercise `.bind`.
      labStore = sigs.LAB_SECRET_STORE;
      vaultCredential = sigs.LAB_SECRET;
      tsigSecret = sigs.LAB_SECRET;
    };

    optional.edge = sigs.CLUSTER_EDGE;

    provides = {
      delivery = sigs.DELIVERY_POLICY;
      exposure = sigs.HOST_EXPOSURE;
      git = sigs.GIT_REPOSITORY;
      cniBootstrap = sigs.CNI_BOOTSTRAP;
    };

    exports = {
      delivery = "argocd/delivery";
      exposure = "gateway/exposure";
      git = "forgejo/git";
      cniBootstrap = "cilium/cniBootstrap";
    };

    # Which provider an optional hole means. Per cluster rather than per
    # consumer: one line here covers every consumer of the signature, and a
    # consumer wanting a different answer overrides with `.bind`.
    defaults = {
      OIDC_PROVIDER = "kanidm";
      LOG_INGEST = "loki";
      METRICS_INGEST = "prometheus";
      TRACE_INGEST = "tempo";
      MESH_ADMIN = "netbird";
    };

    units = _: {
      # Lab-held material, landed where the floe that reads it runs. Declared
      # here with everything else rather than bolted on beside the cluster,
      # which is where two of these used to sit.
      # Two projections, two authored secrets, and each says which it reads. The
      # cluster declares a hole per secret and binds one to each, because
      # `LAB_SECRET` is provided twice here and a hole resolving by itself
      # would be resolving to whichever.
      #
      # `outer:<hole>` is what a filled hole is called inside an inclusion:
      # the parent's resolution becomes an ordinary unit in the inner link, so
      # a unit in here binds to it by name like any other provider.
      vault-token =
        (floes.secret-projection {
          secret = "vault-token";
          namespace = "external-secrets";
          keys.token.from = "token";
        }).bind
          { labSecret = "outer:vaultCredential"; };

      externaldns-tsig =
        (floes.secret-projection {
          secret = "externaldns-tsig";
          namespace = "external-dns";
          keys.tsig-secret.from = "tsig-secret";
        }).bind
          { labSecret = "outer:tsigSecret"; };

      cilium = floes.cilium { };

      # ---- trust ----------------------------------------------------------
      cert-manager = floes.cert-manager { };
      trust-manager = floes.trust-manager { };

      # ---- routing --------------------------------------------------------
      coredns-zone = floes.coredns-zone { };
      # Records for what the gateway routes, pointed at the address the zone's
      # own server answers on — which is the lab's ingress. A k3d Service
      # reports a cluster-internal LoadBalancer address nothing outside can
      # reach, so publishing what each object says would publish that.
      external-dns = floes.external-dns {
        tsigSecretRef = "external-dns/externaldns-tsig";
      };
      # The issuer. Its clients are rendered by whoever needs one — there is no
      # fan-in and nothing here lists them.
      kanidm = floes.kanidm { domain = "idm.${zone}"; };

      # The mesh control plane. Its OIDC client is public and PKCE-based, which
      # is the third shape of consumer kanidm has here — beside harbor's
      # confidential client and forgejo's.
      netbird = floes.netbird { };

      # Beside the control plane, so it resolves both `MESH_NETWORK` and
      # `MESH_ADMIN` locally and the lab says nothing about either. In
      # `homelab.mesh` the same floe runs in a second cluster with neither.
      netbird-operator = floes.netbird-operator { };

      # The first consumer of GIT_REPOSITORY, and the reason it carries two
      # URLs: argo clones from inside the cluster, over forgejo's Service.
      argocd = floes.argocd { };

      forgejo = floes.forgejo {
        oidc = true;
      };

      harbor = floes.harbor {
        oidc = true;
      };

      gateway-api = floes.gateway-api-crds { };
      gateway = floes.gateway {
        tlsEnable = true;
      };
      podinfo = floes.podinfo { };

      # A real cloud cluster, declared and never applied. It renders here so
      # its resource declaration is checked; `examples/labs/tests/cloud.nix` is
      # where the arrangement around it is.
      doks = floes.doks {
        name = "every-floe-workload";
        version = "1.31.1-do.4";
      };

      # Resources rather than bundles. Publishes into the runtime store, so this
      # fixture covers the join between the two and not only the
      # resources on their own.
      provisioned = floes.provisioned {
        stateDir = "/tmp/catallaxy-every-floe";
        publishKey = "provisioned/identity";
      };

      # The escape hatch, instantiated once per app the way a lab would.
      hello = floes.custom {
        name = "hello";
        namespace = "hello";
        servicePort = 5678;

        # The whole of the OIDC redesign, from a consumer's side. `hello`
        # renders its own client into its own namespace; kanidm collects
        # nothing and does not know this app exists.
        oidc = true;
        images.echo = {
          registry = "docker.io";
          repository = "hashicorp/http-echo";
          tag = "1.0";
          digest = null;
        };
        resources.deployment = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          metadata = {
            name = "hello";
            namespace = "hello";
          };
          spec = {
            replicas = 1;
            selector.matchLabels."app.kubernetes.io/name" = "hello";
            template = {
              metadata.labels."app.kubernetes.io/name" = "hello";
              spec.containers = [
                {
                  name = "hello";
                  image = "docker.io/hashicorp/http-echo:1.0";
                  args = [ "-text=hello" ];
                  ports = [ { containerPort = 5678; } ];
                }
              ];
            };
          };
        };
        resources.service = {
          apiVersion = "v1";
          kind = "Service";
          metadata = {
            name = "hello";
            namespace = "hello";
          };
          spec = {
            selector."app.kubernetes.io/name" = "hello";
            ports = [
              {
                port = 5678;
                targetPort = 5678;
              }
            ];
          };
        };
      };

      # ---- operators ------------------------------------------------------
      cnpg = floes.cnpg { };

      crossplane-provider-nop = floes.crossplane-provider-nop { };
      nop-resource = floes.nop-resource { };

      crossplane = floes.crossplane { };
      kaniop = floes.kaniop { };
      redis-operator = floes.redis-operator { };
      reloader = floes.reloader { };
      # The runtime store's server. `lab.units.runtime` names the same
      # address, which is the wiring this floe's VAULT_SERVER exists to make
      # checkable rather than coincidental.
      openbao = floes.openbao { };

      external-secrets = floes.external-secrets { };

      secret-store = floes.secret-store { server = "https://vault.${zone}"; };

      # The two halves of secret sharing, in one cluster because this lab is one
      # cluster. Across two they are what the boundary carries: the publication
      # provides the key and the subscription reads it, which is the same link
      # whether the two sit together or a lab places them apart.
      # Pointed at the CA cert-manager mints, because a publication pushes
      # something that exists: the elaborator refuses a Secret with no creator,
      # which is exactly the mistake an invented name here would be.
      secret-publication = floes.secret-publication {
        namespace = "cert-manager";
        secret = "lab-ca-ca-secret";
        key = "every-floe/lab-ca";
      };

      secret-subscription = floes.secret-subscription {
        secret = "every-floe-copy";
      };

      # ---- storage and telemetry ------------------------------------------
      prometheus = floes.prometheus { };
      openebs = floes.openebs { };
      seaweedfs = floes.seaweedfs { };
      zot = floes.zot { };
      velero = floes.velero {
        schedules.daily = {
          schedule = "0 2 * * *";
          ttl = "168h";
        };
      };
      # All three backends and the issuer are in this lab, so grafana gets three
      # datasources and OIDC login — the full width of both optional holes.
      grafana = floes.grafana {
        oidc = true;
      };

      loki = floes.loki { };
      tempo = floes.tempo { };

      # All three backends are in this lab, so all three pipelines exist. That
      # is the point of the fixture: `every-floe` is where the collector's
      # fan-in is exercised at full width.
      otel-collector = floes.otel-collector { };

      # ---- policy ---------------------------------------------------------
      #
      # No `kapp` floe here, and that is not an omission: `argocd` above answers
      # `DELIVERY_POLICY` for this cluster, and holding `kapp` beside it is two
      # providers of one signature. `policies.oneDelivery` refuses that by name,
      # which is the question being asked — which of these applies this
      # cluster? — so this lab answers argocd and the other labs answer kapp.
    };
  };
}
