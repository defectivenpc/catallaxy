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
  lab.secrets.stores.runtime = {
    backend = "vault";
    vault.server = "https://vault.every-floe.test";
  };

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

  lab.clusters.core.floes = {
    cluster = floes.k3d-cluster {
      name = "core";
      instanceName = "every-floe-core";
    };

    # ---- trust ----------------------------------------------------------
    cert-manager = floes.cert-manager { chart = "${cataCharts.cert-manager.chart}"; };
    trust-manager = floes.trust-manager { chart = "${cataCharts.trust-manager.chart}"; };

    # ---- routing --------------------------------------------------------
    lab-dns = floes.lab-dns {
      inherit (config.lab.dns) zone;
      server = config.lab.network.gateway;
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
    loki = floes.loki { chart = "${cataCharts.loki.chart}"; };
    tempo = floes.tempo { chart = "${cataCharts.tempo.chart}"; };

    # ---- policy ---------------------------------------------------------
    # Installs nothing; it is here so something reads its signature.
    delivery = floes.delivery { };
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
