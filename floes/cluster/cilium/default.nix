# Cilium: the CNI, and the reason a lab can enforce a NetworkPolicy at all.
#
# k3s ships flannel, which implements no NetworkPolicy — a policy applied to a
# flannel cluster is admitted, stored, and enforced by nothing. Swapping the
# CNI is most of why this floe exists.
#
# It is in two halves, and the split is the whole design:
#
#   `mkBootstrapManifest` is a plain function returning a derivation. A CNI
#   must be present before any node becomes Ready, and a floe's bundles are
#   applied to a cluster that is already up, so this half cannot travel
#   through the link graph — the floe would have to `requires` the cluster
#   that cannot start without it. The lab calls the function and hands the
#   result to `k3d-cluster`, which mounts it where k3s applies it at startup.
#
#   The floe proper is an ordinary Helm release that takes ownership
#   afterwards, so upgrades and drift work like every other floe's.
#
# The parked tree did this with `cluster.bootstrapManifests`, a writeback from
# the floe into the cluster's own inputs. That needed a channel the link graph
# does not have, and it is what blocked this migration. Nothing was needed: a
# derivation is not a link-time value, and the lab is already the place that
# knows which provisioner it is configuring.
{
  lib,
  pkgs,
  floe,
  sigs,
  kinds,
  ...
}:

let
  mkValues = import ./values.nix { inherit lib; };

  # A lab calls this and passes the result to its provisioner. It takes the
  # chart rather than reading one, because the lab already pins charts and a
  # second pin here could disagree with the one the floe installs.
  mkBootstrapManifest =
    {
      chart,
      # `localhost` and `6443` are right for k3d, where the agent runs on the
      # same node as the apiserver. A managed control plane needs its real
      # address: there is no network yet to reach a Service over, which is the
      # whole reason this value exists.
      k8sServiceHost ? "localhost",
      k8sServicePort ? "6443",
      hubble ? false,
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
        description = ''
          Store path of the Cilium Helm chart. Required.

          The same chart the lab templated for `mkBootstrapManifest`. Two
          versions is the failure this floe is most exposed to: the release
          would re-render a DaemonSet differing from the running one, the
          agents would restart, and the cluster would lose its network mid-apply.
        '';
      };

      k8sServiceHost = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
        description = "Must match what `mkBootstrapManifest` was given.";
      };

      k8sServicePort = lib.mkOption {
        type = lib.types.str;
        default = "6443";
        description = "Must match what `mkBootstrapManifest` was given.";
      };

      hubble = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run Hubble's relay for flow visibility.

          Must match what `mkBootstrapManifest` was given, for the same reason
          the chart must.
        '';
      };
    };

    requires.cluster = sigs.KUBERNETES_CLUSTER;

    out.component = kinds.component;

    modules = [
      (
        { config, ... }:
        let
          inputs = config.floe.inputs;
          values = mkValues { inherit (inputs) k8sServiceHost k8sServicePort hubble; };
        in
        {
          config.floe.out.component = kinds.mkComponent {
            imagesComplete = true;

            bundles.cilium = kinds.mkBundle {
              # No `createNamespaces`: kube-system is one the cluster ships
              # with, and emitting a Namespace for it has the applier adopt it.
              helmCharts.cilium = {
                inherit (inputs) chart;
                releaseName = "cilium";
                namespace = "kube-system";
                inherit values;
              };

              # Digests, because the chart pins them and the rendered refs
              # carry both — a declaration with `digest = null` does not match
              # what is deployed, and the image gate says so.
              images.agent = {
                registry = "quay.io";
                repository = "cilium/cilium";
                tag = "v1.17.2";
                digest = "sha256:3c4c9932b5d8368619cb922a497ff2ebc8def5f41c18e410bcc84025fcd385b1";
              };
              images.operator = {
                registry = "quay.io";
                repository = "cilium/operator-generic";
                tag = "v1.17.2";
                digest = "sha256:81f2d7198366e8dec2903a3a8361e4c68d47d19c68a0d42f0b7b6e3f0523f249";
              };

              # A second DaemonSet, not an option. Since 1.16 the agent runs
              # its L7 proxy in a separate pod by default, so a cluster that
              # declared only the agent and the operator would mirror into an
              # airgap and find half the datapath missing. The gate caught
              # exactly that.
              images.envoy = {
                registry = "quay.io";
                repository = "cilium/cilium-envoy";
                tag = "v1.31.5-1741765102-efed3defcc70ab5b263a0fc44c93d316b846a211";
                digest = "sha256:377c78c13d2731f3720f931721ee309159e782d882251709cb0fac3b42c03f4b";
              };

              # No `ready` probe, and the reason is the same one otel-collector
              # already records: a DaemonSet has no conditions, so
              # `--for=condition=Ready daemonset/cilium` waits out its whole
              # timeout and then fails. It did, on this lab's first boot —
              # after cilium had already brought the nodes up.
              #
              # `awaitRollout` is the right question for a DaemonSet anyway:
              # every node has the agent, not some quorum of them. The
              # operator is deliberately not the thing waited on — it can be
              # Available on a cluster whose agents are all crash-looping, and
              # the agent is what carries traffic.

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
# The helper travels on the definition, which `lib/lab.nix` keeps reachable:
# `floes.<name>` is the definition with `__functor` set to `instantiate`, so a
# lab writes `floes.cilium { … }` to instantiate and
# `floes.cilium.mkBootstrapManifest { … }` to build the artifact.
cilium // { inherit mkBootstrapManifest; }
