# The lab's secret material, as `cata` reads it.
#
# A collector, and the plural is the whole of the difference from
# `lab-authored-secret`: every store in the lab contributes and every secret
# contributes, and three things come out. Two are the records the CLI needs —
# `catallaxy.labStores` is what `cata secrets edit <store>` resolves against,
# `catallaxy.labSecrets` what it opens — and the third is one step that reads
# each store before anything could want a value out of it.
#
# It answers no signature and installs nothing. A `singleton`, because two
# would emit two steps checking overlapping sets of the same stores.
#
# The step is early on purpose. A lab missing a secret should fail in seconds
# rather than after a cluster exists — so it is before the services and before
# every cluster is created, which is as early as a step can be.
#
# It was six lines in `modules/lab/plan.nix` folding over two option trees.
# The fold is the same; what changes is that the thing doing it is a unit of
# the link, so adding a store to a lab is one statement and nothing has to be
# told about it.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens wants;
in
floe.mkFloe {
  name = "lab-secrets";
  summary = "Every store and secret the lab holds, folded into what `cata` reads, plus the step that proves they open.";

  # One fan-in, so one of these. Two would emit two steps checking overlapping
  # sets of the same stores.
  singleton = true;

  collects = {
    store = sigs.LAB_SECRET_STORE;

    secret = sigs.LAB_SECRET;
  };

  provides.step = sigs.LAB_STEPS;

  # The two things about the lab's authored material that leave the lab, folded
  # from what the store and secret floes provided. Keyed by the floe that
  # provided each, which is the name `cata secrets edit` takes.
  out.labStores = kinds.labStores;
  out.labSecrets = kinds.labSecrets;

  body =
    { collects, ... }:
    let
      authored = lib.attrNames (lib.filterAttrs (_: s: !s.writable) collects.store);
    in
    {
      out.labStores = lib.mapAttrs (
        _: store:
        (removeAttrs store [
          "name"
          "writable"
        ])
        // {
          direction = if store.writable then "runtime" else "authored";
        }
      ) collects.store;

      out.labSecrets = lib.mapAttrs (
        _: secret:
        removeAttrs secret [
          "name"
          "readableKeys"
        ]
      ) collects.secret;

      provides.step.steps = lib.optionalAttrs (collects.secret != { }) {
        ensure-secrets = {
          kind = "ensure-secrets";
          description = "Check the lab's authored secret stores are readable";
          provides = [ planTokens.lab.secrets ];

          before = [ (wants planTokens.lab.services) ];
          beforeClusters = "created";

          params.stores = authored;
        };
      };
    };
}
