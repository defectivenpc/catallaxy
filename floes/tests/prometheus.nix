# prometheus, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe {
    name = "prometheus";
    inputs = {
      chart = "/dev/null";
      crds = "/dev/null";
    };
  };
in
lib.runTests {
  testProvidesItsSignature = {
    expr = r.provides.metrics.readyToken;
    expected = "prometheus/scrape/ready";
  };

  # Two tokens, not one. A floe emitting a ServiceMonitor needs the kind to
  # exist; a floe writing metrics needs the receiver up. They become true at
  # different times and gate different things.
  testTheCrdTokenIsSeparateFromReadiness = {
    expr = r.provides.metrics.crdsEstablished != r.provides.metrics.readyToken;
    expected = true;
  };

  # `enableRemoteWriteReceiver` is what makes this address answer at all;
  # without it the endpoint 404s and a writer retries forever against a
  # Prometheus that is otherwise healthy.
  testRemoteWriteIsEnabled = {
    expr =
      r.bundles.prometheus.helmCharts.prometheus.values.prometheus.prometheusSpec.enableRemoteWriteReceiver;
    expected = true;
  };

  # The CRDs are a bundle of their own, so the chart must not also install
  # them — two owners of one cluster-scoped resource is a fight on every
  # upgrade.
  testTheChartDoesNotInstallTheCrds = {
    expr = r.bundles.prometheus.helmCharts.prometheus.values.crds.enabled;
    expected = false;
  };

  # The alternative is a Job that mints a certificate with a CA of its own and
  # patches it into the webhook config: an imperative step in the middle of a
  # declarative apply.
  testTheAdmissionWebhookUsesCertManager = {
    expr =
      r.bundles.prometheus.helmCharts.prometheus.values.prometheusOperator.admissionWebhooks.patch.enabled;
    expected = false;
  };

  # The stack bundles Grafana. A lab that wants one enables the floe, which is
  # configured, routed and checked.
  testItDoesNotSmuggleInGrafana = {
    expr = r.bundles.prometheus.helmCharts.prometheus.values.grafana.enabled;
    expected = false;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
