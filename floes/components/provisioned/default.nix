# A floe whose delivery is `resources` rather than bundles.
#
# Resources and bundles are not two kinds of floe. This one takes inputs, requires the
# cluster, and emits an output kind, exactly as every bundle floe does; what
# differs is which kind. That is the claim made about registering
# a category, and this is the smallest thing that tests it.
#
# It is deliberately built on providers that reach no network and no account:
# `random` mints a value, `local` writes files. A stack of those runs a real
# plan, a real apply, real state and a real destroy in about a second, which
# is what makes the whole category iterable without a cloud.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "provisioned";
  summary = "A fixture resource floe: mints a value and writes a local file.";

  inputs = {
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/tmp/catallaxy-provisioned";
      description = ''
        Directory the `local` resources write into.

        A real resource would name a cloud account here. This names a path,
        because the point of the fixture is the machinery around the resource
        rather than the resource.
      '';
    };

    publishKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "shared/credential";
      description = ''
        Key the generated credential is published under, or null to generate
        it and let it stay in state.

        This is the join between resources and bundles and the easiest thing
        in the design to get wrong. *Which* store is resolved —
        `optional.labStore` — so only the key is written here, and a cluster
        reads it back by resolving the same store.
      '';
    };
  };

  # A resource floe still targets a cluster. It is a member like any other,
  # and `componentsTargetTheCluster` would refuse it otherwise.
  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # Which lab store the credential lands in, resolved rather than spelled.
  optional.labStore = sigs.LAB_SECRET_STORE;

  out.resources = kinds.resources;
  out.publications = kinds.publications;

  modules = [
    (
      {
        config,
        lib,
        floe,
        ...
      }:
      let
        inputs = config.floe.inputs;
        labStore = config.floe.requires.labStore;
      in
      {
        config.floe.out.resources = {
          identity = {
            provider = "random";
            type = "random_password";
            inputs = {
              length = 32;
              special = false;
            };
            outputs = [ "result" ];
            phase = "before-clusters";
          };

          marker = {
            provider = "local";
            type = "local_file";
            inputs = {
              filename = "${inputs.stateDir}/identity";
              content = floe.mkDeferred sigs.RESOURCE_OUTPUT {
                resource = "identity";
                output = "result";
              };
            };
            outputs = [ "id" ];
            phase = "before-clusters";
          };
        };

        config.floe.out.publications = lib.optionalAttrs (inputs.publishKey != null) {
          credential = {
            resource = "identity";
            output = "result";
            store =
              if labStore != null then
                labStore.name
              else
                throw (
                  "provisioned: publishKey is '${inputs.publishKey}' and no LAB_SECRET_STORE "
                  + "resolved, so there is nowhere to publish it."
                );
            key = inputs.publishKey;
          };
        };
      }
    )
  ];
}
