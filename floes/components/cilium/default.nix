# Cilium: the CNI, and the reason a lab can enforce a NetworkPolicy at all.
#
# k3s ships flannel, which implements no NetworkPolicy — a policy applied to a
# flannel cluster is admitted, stored, and enforced by nothing. Swapping the
# CNI is most of why this floe exists.
#
# It is in two halves, and one floe owns both:
#
#   The bootstrap manifest, provided as `CNI_BOOTSTRAP`. A CNI must be present
#   before any node becomes Ready, and a floe's bundles are applied to a
#   cluster that is already up — so the provisioner applies this one, reading
#   it off the hole the cluster exports it through.
#
#   The release, an ordinary Helm chart that takes ownership afterwards, so
#   upgrades and drift work like every other floe's.
#
# Both render from the same inputs, which is the point: a lab used to call
# `mkBootstrapManifest` itself and pass the result to `k3d-cluster` alongside
# `disableFlannel = true`, so three of the inputs below were documented as
# "must match what `mkBootstrapManifest` was given" and nothing checked that
# they did. Setting one half alone gave either nodes that never become Ready
# or two CNIs writing over each other.
#
# What made that necessary was a claim living *inside* its cluster, leaving no
# direction for a component to reach the thing that establishes it. A claim is
# a unit beside its cluster now, so there is one.
{
  floe,
  cataCharts ? null,
  lib,
  pkgs,
  sigs,
  kinds,
  ...
}:

let
  mkValues = import ./values.nix { inherit lib; };

  # Rendered from the floe's own inputs, so the release and the bootstrap
  # cannot be two versions of the chart — the failure this floe is most
  # exposed to, since the release would re-render a DaemonSet differing from
  # the running one and the agents would restart mid-apply.
  bootstrapManifest =
    {
      chart,
      k8sServiceHost,
      k8sServicePort,
      hubble,
    }:
    let
      values = pkgs.writeText "cilium-bootstrap-values.json" (
        builtins.toJSON (mkValues {
          inherit k8sServiceHost k8sServicePort hubble;
        })
      );
    in
    pkgs.runCommand "cilium-bootstrap.yaml" { nativeBuildInputs = [ pkgs.kubernetes-helm ]; } ''
      helm template cilium ${chart} \
        --namespace kube-system \
        --values ${values} \
        > $out
    '';

  cilium = floe.mkFloe {
    name = "cilium";
    summary = "Cilium as the cluster's CNI, replacing the provisioner's default.";

    inputs = {
      chart = lib.mkOption {
        type = lib.types.str;
        default = "${cataCharts.cilium.chart}";
        defaultText = lib.literalExpression "cataCharts.cilium.chart";
        description = ''
          Store path of the Cilium Helm chart, defaulted from the pin.

          One pin for both halves. Two versions is the failure this floe is
          most exposed to: the release would re-render a DaemonSet differing
          from the running one, the agents would restart, and the cluster
          would lose its network mid-apply.
        '';
      };

      k8sServiceHost = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = ''
          Where the agents reach the API server before there is a network to
          reach a Service over.

          `localhost` is right for k3d, where the agent runs on the same node
          as the apiserver. A managed control plane needs its real address.
        '';
      };

      k8sServicePort = lib.mkOption {
        type = lib.types.str;
        default = "6443";
        description = "Port the API server answers on, for the same reason.";
      };

      hubble = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Hubble's relay for flow visibility.";
      };
    };

    requires.cluster = sigs.KUBERNETES_CLUSTER;
    provides.cniBootstrap = sigs.CNI_BOOTSTRAP;
    out.component = kinds.component;
    modules = [
      (
        { config, ... }:
        let
          inputs = config.floe.inputs;
          values = mkValues { inherit (inputs) k8sServiceHost k8sServicePort hubble; };
        in
        {
          config.floe.provides.cniBootstrap = {
            name = "cilium";
            manifest = "${bootstrapManifest {
              inherit (inputs)
                chart
                k8sServiceHost
                k8sServicePort
                hubble
                ;
            }}";
          };

          config.floe.out.component = kinds.mkComponent {
            imagesComplete = true;

            bundles.cilium = kinds.mkBundle {
              helmCharts.cilium = kinds.mkHelmChart {
                inherit (inputs) chart;
                releaseName = "cilium";
                namespace = "kube-system";
                inherit values;
              };

              images.agent = kinds.mkImage "quay.io/cilium/cilium:v1.17.2@sha256:3c4c9932b5d8368619cb922a497ff2ebc8def5f41c18e410bcc84025fcd385b1";
              images.operator = kinds.mkImage "quay.io/cilium/operator-generic:v1.17.2@sha256:81f2d7198366e8dec2903a3a8361e4c68d47d19c68a0d42f0b7b6e3f0523f249";

              images.envoy = kinds.mkImage "quay.io/cilium/cilium-envoy:v1.31.5-1741765102-efed3defcc70ab5b263a0fc44c93d316b846a211@sha256:377c78c13d2731f3720f931721ee309159e782d882251709cb0fac3b42c03f4b";

              ops.network = {
                status = kinds.mkOpsCommand {
                  description = "Cilium's own view of the datapath, per node";
                  command = [
                    "kubectl"
                    "-n"
                    "kube-system"
                    "exec"
                    "ds/cilium"
                    "--"
                    "cilium-dbg"
                    "status"
                  ];
                };
              };
            };
          };
        }
      )
    ];
  };
in
cilium
