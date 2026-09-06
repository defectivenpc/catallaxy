# The canonical form of `lab.out.cliConfig`, one file per lab.
#
# `cliConfig` is the document `cata` parses, and until this existed nothing
# pinned it. `manifest-digest-<lab>` walks `lab.out.package`, and
# `metadata.json` carries only projections, assertions and the deployment
# plan — so `provisioner`, `provisionerConfig`, `kubernetes`, `network` and
# `kubeContext` reached the CLI through a document no check had ever read.
# A change to any of them moved nothing anybody would notice.
#
# One derivation rather than a pipeline written twice: the check diffs
# against this and `refresh-cli-configs` copies out of it, so the two consume
# the identical store path and cannot drift. `manifest-digest` and
# `refresh-digests` hold two copies of one pipeline and carry a comment
# saying they must stay byte-identical; this needs no such comment.
{
  lib,
  pkgs,
  labDefs,
}:

let
  # Both plans come out. They are already pinned byte for byte by
  # `plan-deploy-<lab>` and `plan-teardown-<lab>`, in text a human reads
  # rather than as a JSON blob, and a plan is most of the document — leaving
  # them in would make every plan change fail two checks and bury this one's
  # diff in the noise of the other's.
  omitted = [
    "deploymentPlan"
    "teardownPlan"
  ];

  canonical =
    name: lab:
    pkgs.runCommand "cli-config-${name}.json"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.gnused
        ];
        raw = builtins.toJSON (removeAttrs lab.config.lab.out.cliConfig omitted);
        passAsFile = [ "raw" ];
      }
      ''
        # `-S` and the default pretty-printing together: sorted keys make the
        # file stable across an attrset reordering, and one field per line is
        # what makes the diff readable when it fires. A single-line blob would
        # report every change as "the whole file".
        #
        # Store hashes normalised for the same reason `manifest-digest` does
        # it: `opsToolPath` moves whenever nixpkgs rebuilds the wrapper, and a
        # fixture that churned on every input bump would be refreshed without
        # being read.
        jq -S . < "$rawPath" \
          | sed 's|/nix/store/[a-z0-9]\{32\}-|/nix/store/HASH-|g' > $out
      '';
in
pkgs.runCommand "cli-configs" { } ''
  mkdir -p $out
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: lab: "cp ${canonical name lab} $out/${name}.json") labDefs
  )}
''
