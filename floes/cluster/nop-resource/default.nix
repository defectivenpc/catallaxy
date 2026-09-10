# A managed resource that reconciles to Ready and creates nothing.
#
# The reconcile camp's `podinfo`: the smallest thing that proves the path
# works. It exists so a lab can run the whole Crossplane lifecycle — provider
# healthy, CR applied, condition reached, deleted on teardown — without an
# account, the way `provisioned` does for the state-based camp.
{
  catallaxy,
  lib,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "nop-resource";
  summary = "A Crossplane managed resource that goes Ready on a timer and creates nothing.";

  inputs = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "nop";
      description = "Name of the NopResource.";
    };

    readyAfter = lib.mkOption {
      type = lib.types.str;
      default = "10s";
      description = ''
        How long the provider waits before reporting Ready.

        Its poll interval is 10s, so anything finer is rounded up to one poll
        and a lab that asked for `1s` waits the same as one that asked for
        `10s`. Stated rather than defaulted low, so the readiness timeout
        below is visibly larger than this.
      '';
    };
  };

  requires.resourceProvider = sigs.MANAGED_RESOURCE_PROVIDER;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.out.component = kinds.mkComponent {
          # Nothing to pull: the resource is reconciled by the provider's
          # controller, which the provider floe declares.
          imagesComplete = true;

          bundles.nop = kinds.mkBundle {
            resources.nop = {
              apiVersion = "nop.crossplane.io/v1alpha1";
              kind = "NopResource";
              metadata.name = inputs.name;
              spec.forProvider.conditionAfter = [
                {
                  time = inputs.readyAfter;
                  conditionType = "Ready";
                  conditionStatus = "True";
                }
              ];
            };

            ready = kinds.readyCondition {
              resource = "nopresource/${inputs.name}";
              condition = "Ready";
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
