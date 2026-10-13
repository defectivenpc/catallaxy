# provider-nop: managed resources that reconcile without a cloud.
#
# What `local` and `random` are to OpenTofu. A `NopResource` reaches
# Ready on a timer and touches nothing, so the whole reconcile path — the
# provider installing, its CRDs registering, a resource going Ready, adopt and
# delete on teardown — runs in the e2e matrix with no account behind it.
#
# It cannot stand in for the cross-cluster half: a nop resource emits only the
# connection details it was handed, and `sync-kubeconfig` wants a kubeconfig
# that reaches a cluster that exists. That needs a real provider.
{
  floe,
  lib,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "crossplane-provider-nop";
  summary = "The nop Crossplane provider, whose managed resources reconcile without touching anything.";

  inputs = {
    package = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/crossplane-contrib/provider-nop:v0.4.0";
      description = ''
        The provider package. Crossplane pulls this itself rather than the
        applier doing it, which is why it is declared in `images` even though
        no rendered pod spec names it.

        `ghcr.io` rather than `xpkg.upbound.io`: both publish this package at
        the same digest, and the lab's pull-through cache already mirrors the
        first. A lab whose nodes resolve through its own DNS cannot reach an
        unmirrored registry at all — that server is authoritative for the zone
        and answers REFUSED for everything else.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "provider-nop";
      description = "Name of the Provider object, and the prefix of the pod it runs.";
    };
  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.controlPlane = sigs.MANAGED_RESOURCE_CONTROL_PLANE;
  provides.resourceProvider = sigs.MANAGED_RESOURCE_PROVIDER;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        controlPlane = config.floe.requires.controlPlane;

        crdKinds = [ "nop.crossplane.io/NopResource" ];

        healthy = "managed-resources/${inputs.name}/healthy";
      in
      {
        config.floe.provides.resourceProvider = {
          inherit crdKinds healthy;
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;
          backs.resourceProvider = [ "provider" ];

          bundles.provider = kinds.mkBundle {
            crds = crdKinds;

            images.provider = kinds.mkImage inputs.package;

            resources.provider = {
              apiVersion = "pkg.crossplane.io/v1";
              kind = "Provider";
              metadata.name = inputs.name;
              spec.package = inputs.package;
            };

            ready = kinds.readyCondition {
              resource = "provider/${inputs.name}";
              condition = "Healthy";
              namespace = controlPlane.namespace;
              timeout = "5m";
            };
          };
        };
      }
    )
  ];
}
