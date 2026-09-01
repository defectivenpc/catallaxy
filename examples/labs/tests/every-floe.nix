# Every floe in the catalogue, enabled somewhere.
#
# The example labs are labs someone would build. This is not: it exists
# because a floe no lab renders is a floe whose declarations nothing checks —
# its images are never scraped, its bundles never laid out, its signature
# never resolved against a real peer. A migration that leaves a floe
# unexercised has not finished with it.
#
# It renders and snapshots like any other lab and never enters the e2e set,
# which is what makes it the cheap place to keep this honest.
#
# Grouped into clusters only where floes cannot share one. Right now they all
# can, so there is one; a second appears when something claims a capability
# another floe already holds.
{
  lib,
  cataCharts,
  k8sSpecs,
  floes,
  config,
  ...
}:
{
  lab.name = "every-floe";
  lab.dns.zone = "every-floe.test";
  lab.network.subnet = "172.30.0.0/16";

  # The store floe authenticates with a token it does not create. Authored in
  # sops and projected in, which is the shape the floe's docstring describes
  # and what keeps the cluster's coherence check satisfiable.
  lab.secrets.stores.authored.backend = "sops";
  # No `vault.server`. openbao is in this cluster and knows its own address;
  # naming one here would be a second place for it, and the two disagree
  # silently because nothing dials the URL until something reads a secret.
  # `modules/lab/out.nix` fills it from whatever provides VAULT_SERVER.
  lab.secrets.stores.runtime.backend = "vault";

  lab.secrets.managed.vault-credential = {
    store = "authored";
    keys.token = {
      generator = "hex";
      length = 32;
    };
  };

  lab.clusters.core.secrets.project.vault-token = {
    source = "vault-credential";
    namespace = "external-secrets";
    keys.token.from = "token";
  };

  # external-dns authenticates to the RFC2136 server with a TSIG key it does
  # not create either. Same shape as the vault token, and the reason the floe
  # takes a reference rather than the value: a key in a Helm value renders
  # into the Deployment's argv.
  lab.secrets.managed.externaldns-tsig = {
    store = "authored";
    keys.tsig-secret = {
      generator = "base64";
      length = 32;
    };
  };

  lab.clusters.core.secrets.project.externaldns-tsig = {
    source = "externaldns-tsig";
    namespace = "external-dns";
    keys.tsig-secret.from = "tsig-secret";
  };

  lab.clusters.core.floes = {
    # Both halves of cilium, which is the point of having it here: the
    # bootstrap manifest is a derivation the lab hands to the provisioner, and
    # the floe below installs the same chart as a release that takes ownership
    # once the cluster is up. One `cataCharts.cilium.chart` feeds both, so the
    # two cannot disagree about what is running.
    cluster = floes.k3d-cluster {
      name = "core";
      instanceName = "every-floe-core";

      disableFlannel = true;
      autoDeployManifests = [
        {
          name = "cilium";
          path = "${floes.cilium.mkBootstrapManifest { chart = "${cataCharts.cilium.chart}"; }}";
        }
      ];
    };

    cilium = floes.cilium { chart = "${cataCharts.cilium.chart}"; };

    # ---- trust ----------------------------------------------------------
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    trust-manager = floes.trust-manager { chart = "${cataCharts.trust-manager.chart}"; };

    # ---- routing --------------------------------------------------------
    lab-dns = floes.lab-dns {
      inherit (config.lab.dns) zone;
      server = config.lab.network.gateway;
    };
    # Records for what the gateway routes. `defaultTargets` because a k3d
    # Service reports a cluster-internal LoadBalancer address that nothing
    # outside the cluster can reach.
    external-dns = floes.external-dns {
      chart = "${cataCharts.external-dns.chart}";
      inherit (config.lab.dns) zone;
      dnsServer = config.lab.network.gateway;
      tsigSecretRef = "external-dns/externaldns-tsig";
      defaultTargets = [ config.lab.network.gateway ];
    };
    # The issuer. Its clients are rendered by whoever needs one — there is no
    # fan-in and nothing here lists them.
    kanidm = floes.kanidm { domain = "idm.${config.lab.dns.zone}"; };

    # The first consumer of GIT_REPOSITORY, and the reason it carries two
    # URLs: argo clones from inside the cluster, over forgejo's Service.
    argocd = floes.argocd { chart = "${cataCharts.argocd.chart}"; };

    forgejo = floes.forgejo {
      chart = "${cataCharts.forgejo.chart}";
      oidc = true;
    };

    harbor = floes.harbor {
      chart = "${cataCharts.harbor.chart}";
      oidc = true;
    };

    gateway-api = floes.gateway-api-crds {
      manifest = "${k8sSpecs.standaloneCrds.gateway-api}";
      version = "v1.2.1";
    };
    gateway = floes.gateway {
      chart = "${cataCharts.traefik.chart}";
      baseDomain = config.lab.dns.zone;
      tlsEnable = true;
    };
    podinfo = floes.podinfo { };

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
    cnpg = floes.cnpg { chart = "${cataCharts.cnpg.chart}"; };
    kaniop = floes.kaniop { chart = "${cataCharts.kaniop.chart}"; };
    redis-operator = floes.redis-operator { chart = "${cataCharts.redis-operator.chart}"; };
    reloader = floes.reloader { chart = "${cataCharts.reloader.chart}"; };
    # The runtime store's server. `lab.secrets.stores.runtime.vault` above
    # names the same address, which is the wiring this floe's VAULT_SERVER
    # exists to make checkable rather than coincidental.
    openbao = floes.openbao { chart = "${cataCharts.openbao.chart}"; };

    external-secrets = floes.external-secrets {
      chart = "${cataCharts.external-secrets.chart}";
      crds = "${cataCharts.external-secrets.crds}";
    };

    secret-store = floes.secret-store {
      labStore = "runtime";
      server = "https://vault.${config.lab.dns.zone}";
    };

    # ---- storage and telemetry ------------------------------------------
    prometheus = floes.prometheus {
      chart = "${cataCharts.prometheus.chart}";
      crds = "${cataCharts.prometheus.crds}";
    };
    openebs = floes.openebs { chart = "${cataCharts.openebs.chart}"; };
    seaweedfs = floes.seaweedfs { chart = "${cataCharts.seaweedfs.chart}"; };
    zot = floes.zot { chart = "${cataCharts.zot.chart}"; };
    velero = floes.velero {
      chart = "${cataCharts.velero.chart}";
      crds = "${cataCharts.velero.crds}";
      schedules.daily = {
        schedule = "0 2 * * *";
        ttl = "168h";
      };
    };
    # All three backends and the issuer are in this lab, so grafana gets three
    # datasources and OIDC login — the full width of both optional holes.
    grafana = floes.grafana {
      chart = "${cataCharts.grafana.chart}";
      oidc = true;
    };

    loki = floes.loki { chart = "${cataCharts.loki.chart}"; };
    tempo = floes.tempo { chart = "${cataCharts.tempo.chart}"; };

    # All three backends are in this lab, so all three pipelines exist. That
    # is the point of the fixture: `every-floe` is where the collector's
    # fan-in is exercised at full width.
    otel-collector = floes.otel-collector { chart = "${cataCharts.otel-collector.chart}"; };

    # ---- policy ---------------------------------------------------------
    # Installs nothing; it is here so something reads its signature.
    # No `delivery` floe here. It answers DELIVERY_POLICY with "kapp
    # applies", which is what a lab gets when nothing provides the signature
    # at all — and `argocd` above answers the same signature with a real CD
    # tool behind it. Two answers to one question is what `modules/lab/cd.nix`
    # refuses, and it refused this.
  };

  # Every floe the set ships is instantiated above. When one is added and
  # this is not, the lab that was supposed to catch it says so instead.
  lab.assertions = [
    (
      let
        shipped = lib.attrNames (import ../../../floes).cluster;

        # Read off the instances rather than the attribute names: a lab names
        # *units*, and a unit may be called anything. `def.name` is what floe
        # it actually is.
        rendered = map (i: i.def.name) (lib.attrValues config.lab.clusters.core.floes);

        missing = lib.subtractLists rendered shipped;
      in
      {
        assertion = missing == [ ];
        message =
          "every-floe does not render: ${lib.concatStringsSep ", " missing}. "
          + "A floe no lab renders is a floe whose declarations nothing checks.";
      }
    )
  ];
}
