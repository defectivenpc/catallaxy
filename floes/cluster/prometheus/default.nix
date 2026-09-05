# Prometheus, via kube-prometheus-stack.
#
# Rebuilt against RFC 0001 rather than ported. The parked floe carried a
# 402-line option surface and the example labs between them set exactly two
# things on it — a remote-write URL read off its exports, and a gateway block.
# What is here is what a lab exercises plus what a consumer has to be told.
#
# The CRDs are their own bundle because the chart cannot install them: with
# `crds.enabled = false` the chart renders the operator against kinds it
# assumes already exist, and the stripped-down CRD file is 1.4 MB of schema
# that has no business being re-rendered on every change to a Prometheus
# option.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "prometheus";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the kube-prometheus-stack Helm chart. Required.";
    };

    crds = lib.mkOption {
      type = lib.types.str;
      description = ''
        Store path of the stripped-down CRD manifest. Required.

        Separate from the chart because the operator's own release pins a
        different CRD version than the chart bundles, and because a chart that
        installs CRDs re-applies them on every upgrade.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "monitoring";
      description = "Namespace the operator and the Prometheus run in.";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "7d";
      description = "How long samples are kept.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "10Gi";
      description = "Size of the Prometheus volume claim.";
    };

    storageClass = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Storage class for that claim. Null takes the cluster's default.";
    };

    # Off by default, all three. A lab that wants a node exporter on every node
    # is saying something; a lab that gets one because a chart default said so
    # is not.
    alertmanager = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run Alertmanager beside Prometheus.";
    };

    nodeExporter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run node-exporter as a DaemonSet.";
    };

    kubeStateMetrics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run kube-state-metrics.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # The operator's admission webhook is fronted by a certificate cert-manager
  # issues. The chart's alternative is a `patch` Job that generates one with a
  # self-signed CA of its own and writes it back into the webhook config — an
  # imperative step in the middle of a declarative apply.
  requires.webhook = sigs.X509_WEBHOOK;
  requires.issuance = sigs.X509_ISSUANCE;

  provides.metrics = sigs.METRICS_INGEST;
  out.component = kinds.component;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        issuance = config.floe.requires.issuance;

        scrapeReady = "prometheus/scrape/ready";
        crdsEstablished = "prometheus/crds/established";

        # The chart's own names. `prometheus-kube-prometheus-prometheus` is the
        # release name doubled because the chart prefixes its own name onto the
        # release's — it looks like a mistake and is not.
        service = "prometheus-kube-prometheus-prometheus";
        statefulSet = "prometheus-prometheus-kube-prometheus-prometheus";

        base = "http://${service}.${inputs.namespace}.svc.cluster.local:9090";

        crdKinds = map (k: "monitoring.coreos.com/${k}") [
          "Alertmanager"
          "AlertmanagerConfig"
          "PodMonitor"
          "Probe"
          "Prometheus"
          "PrometheusAgent"
          "PrometheusRule"
          "ScrapeConfig"
          "ServiceMonitor"
          "ThanosRuler"
        ];
      in
      {
        config.floe.provides.metrics = {
          inherit crdsEstablished crdKinds;
          queryUrl = base;

          # `enableRemoteWriteReceiver` below is what makes this address
          # answer. Without it the endpoint 404s and a remote writer retries
          # forever against a Prometheus that is otherwise healthy.
          remoteWriteUrl = "${base}/api/v1/write";
        };

        config.floe.out.component = kinds.mkComponent {
          backs.metrics = [
            "crds"
            "prometheus"
          ];

          imagesComplete = true;

          network = {
            declared = true;
            serves.api.port = 9090;
            # It scrapes every target in the cluster, which is not a set that
            # can be named here.
            serves.scrape.port = 9090;
          };

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.crds ];
            crds = crdKinds;

            # Nothing to roll out: applying the file is the whole of it, and
            # the `kind:` edges the elaborator derives are what make consumers
            # wait for the types rather than for this bundle.
            awaitRollout = false;
          };

          bundles.prometheus = kinds.mkBundle {
            needs = [ "crds" ];
            createNamespaces = [ inputs.namespace ];

            helmCharts.prometheus = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "prometheus";
              values = {
                # Installed by the bundle above, which owns them.
                crds.enabled = false;

                prometheusOperator.admissionWebhooks = {
                  certManager = {
                    enabled = true;
                    issuerRef = issuance.issuerRef;
                  };
                  patch.enabled = false;
                };

                prometheus.prometheusSpec = {
                  inherit (inputs) retention;
                  enableRemoteWriteReceiver = true;
                  storageSpec.volumeClaimTemplate.spec = {
                    accessModes = [ "ReadWriteOnce" ];
                    resources.requests.storage = inputs.storage;
                  }
                  // lib.optionalAttrs (inputs.storageClass != null) {
                    storageClassName = inputs.storageClass;
                  };
                };

                alertmanager.enabled = inputs.alertmanager;
                nodeExporter.enabled = inputs.nodeExporter;
                kubeStateMetrics.enabled = inputs.kubeStateMetrics;

                # The stack bundles Grafana. A lab that wants one enables the
                # grafana floe, which is configured, routed and checked; one
                # that arrives as a chart default is none of those.
                grafana.enabled = false;
              };
            };

            # Only the operator appears in the rendered manifests. The other
            # two are pulled by the *operator* at runtime from the Prometheus
            # CR, so `images-complete-*` cannot see them — it compares what
            # rendered against what was declared, and these render nowhere.
            #
            # Which means they have to be read off the chart's `values.yaml`
            # and will drift silently when it is bumped. `prometheus.tag` is
            # pinned there; the config reloader's is empty and falls back to
            # `Chart.yaml`'s `appVersion`, which is the operator's version.
            images.operator = {
              registry = "quay.io";
              repository = "prometheus-operator/prometheus-operator";
              tag = "v0.82.2";
              digest = null;
            };
            images.prometheus = {
              registry = "quay.io";
              repository = "prometheus/prometheus";
              tag = "v3.4.0";
              digest = null;
            };
            images.configReloader = {
              registry = "quay.io";
              repository = "prometheus-operator/prometheus-config-reloader";
              tag = "v0.82.2";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "statefulset/${statefulSet}";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "10m";
            };

            verify.scrapes-itself = {
              description = "Prometheus is up and scraping";
              timeout = "5m";
              expect = {
                apiVersion = "monitoring.coreos.com/v1";
                kind = "Prometheus";
                metadata.namespace = inputs.namespace;
              };
              reject = [ ];
            };
          };
        };
      }
    )
  ];
}
