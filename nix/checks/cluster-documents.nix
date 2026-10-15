# Every lab's document, through the parser that reads it.
#
# `cliConfig-<lab>` pins the document byte for byte, which catches one that
# *changed* and not one `cata` cannot read. The two are different failures: a
# field renamed on the Nix side moves the diff, refreshing it makes the check
# pass again, and the CLI goes on looking for the old name and finding
# nothing. That is the half of the tightness law a diff cannot state — nothing
# a command reads that the document does not carry — and the only way to state
# it is to parse.
#
# It parses the *whole* document rather than the committed copy, which omits
# both plans on purpose: a projection of the thing the CLI is handed is not
# the thing the CLI is handed.
#
# It earned its keep on its first run. `provisioning.wait` was emitted as
# `waitTimeout`, so the two halves of the slice that split the two waits
# disagreed about the name of one of them, and every digest, every plan and
# every byte-diff passed.
{
  lib,
  pkgs,
  packages,
  labDefs,
}:

let
  cata = packages.cataWrapped;

  one =
    name: lab:
    let
      document = pkgs.writeText "${name}.json" (builtins.toJSON lab.cliConfig);
    in
    pkgs.runCommand "cluster-document-${name}" { } ''
      if ! ${cata}/bin/cata lab parse --from-file ${document} > $out 2>&1; then
        cat $out >&2
        echo "" >&2
        echo "cata cannot parse the document it is handed for '${name}'." >&2
        echo "" >&2
        echo "The document and the parser are two halves of one declaration," >&2
        echo "so whichever moved, both have to: the field names in" >&2
        echo "modules/lab/cluster/default.nix and the structs in cli/src/domain/." >&2
        exit 1
      fi
    '';
  # And every cluster's own artifact, read on its own.
  #
  # This is the operational test of whether a cluster is a concept in its own
  # right: `cata cluster parse` is handed the document and nothing else — no
  # flake, no lab, no name to resolve — so a field that leaks back to the lab
  # fails here naming the field. `cluster up` answers the same question for
  # real and cannot run in a sandbox, which has no docker.
  artifact =
    labName: clusterName: cluster:
    let
      document = pkgs.writeText "cluster.json" (builtins.toJSON cluster.spec);
    in
    pkgs.runCommand "cluster-artifact-${labName}-${clusterName}" { } ''
      if ! ${cata}/bin/cata cluster parse ${document} > $out 2>&1; then
        cat $out >&2
        echo "" >&2
        echo "'${clusterName}' in '${labName}' cannot be read on its own." >&2
        echo "" >&2
        echo "A cluster denotes a claim and its content, so everything needed" >&2
        echo "to stand one up is in its own document. Whatever is missing here" >&2
        echo "is a fact that stayed behind in the lab." >&2
        exit 1
      fi
    '';

  artifacts = lib.concatMap (
    labName:
    lib.mapAttrsToList (clusterName: cluster: {
      name = "cluster-artifact-${labName}-${clusterName}";
      value = artifact labName clusterName cluster;
    }) labDefs.${labName}.clusters
  ) (lib.attrNames labDefs);
in
lib.mapAttrs' (name: lab: lib.nameValuePair "cluster-document-${name}" (one name lab)) labDefs
// lib.listToAttrs artifacts
