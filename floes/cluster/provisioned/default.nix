# A floe whose delivery is `resources` rather than bundles — RFC 0003.
#
# The two camps are not two kinds of floe. This one takes inputs, requires the
# cluster, and emits an output kind, exactly as every bundle floe does; what
# differs is which kind. That is the claim RFC 0003 §0 makes about registering
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
  summary = "A fixture floe in the resources camp: mints a value and writes a local file.";

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

    publishTo = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            store = lib.mkOption {
              type = lib.types.str;
              description = "A `lab.secrets.stores` entry the generated value lands in.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              description = "Key inside that store.";
            };
          };
        }
      );
      default = null;
      description = ''
        Where the generated credential is published, or null to generate it
        and let it stay in state.

        This is the join between the two camps (RFC 0003 §7) and the easiest
        thing in the design to get wrong: a publication writes into a store
        the lab already declares, and a cluster reads it back with the
        `secrets.subscribe` it already has. There is no second addressing
        scheme, because a second one would be understood by neither side.
      '';
    };
  };

  # A resource floe still targets a cluster. It is a member like any other,
  # and `componentsTargetTheCluster` would refuse it otherwise.
  requires.cluster = sigs.KUBERNETES_CLUSTER;

  out.resources = kinds.resources;
  out.publications = kinds.publications;

  modules = [
    (
      # `floe` here is the per-unit helper the linker passes in, not the
      # library the file above is written against — `mkDeferred` is bound to
      # this unit's link name, which is what makes a token say where it came
      # from without the body repeating its own name.
      {
        config,
        lib,
        floe,
        ...
      }:
      let
        inputs = config.floe.inputs;
      in
      {
        config.floe.out.resources = {
          # Runs before any cluster exists — the case the reconcile camp
          # cannot cover at all, because before a cluster there is no
          # reconciler, no CRD, and nowhere to put a credential.
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

          # And one that reads it. Same unit, same phase, so this is direct
          # interpolation inside one state file and the tool orders the two
          # itself — we do not re-implement its dependency graph.
          marker = {
            provider = "local";
            type = "local_file";
            inputs = {
              filename = "${inputs.stateDir}/identity";
              content = floe.mkDeferred [
                "identity"
                "result"
              ];
            };
            outputs = [ "id" ];
            phase = "before-clusters";
          };
        };

        config.floe.out.publications = lib.optionalAttrs (inputs.publishTo != null) {
          credential = {
            resource = "identity";
            output = "result";
            inherit (inputs.publishTo) store key;
          };
        };
      }
    )
  ];
}
