# Floe verify checks -> one Chainsaw Test per cluster.
#
# `cata lab verify` runs `$out/verify/<cluster>/chainsaw-test.yaml` if it is
# there and skips the check silently if it is not, so a cluster whose floes
# declared nothing renders an empty directory rather than an empty Test.
{ lib, pkgs }:

let
  yamlUtil = import ./yaml.nix { inherit lib pkgs; };
  verifyTypes = import ../verify-types.nix { inherit lib; };
in
{
  # mkVerifyTest :: { labName; clusterName; checks } -> package
  #
  # `checks` is `cluster.out.verify`: the lifted channel, keyed
  # `<unit>/<bundle>/<check>`, whose values are the floe's `verifyCheckSchema`
  # records.
  mkVerifyTest =
    {
      labName,
      clusterName,
      checks,
    }:
    let
      steps = lib.concatLists (
        lib.mapAttrsToList (
          name: check:
          verifyTypes.stepsFor {
            # A Chainsaw step name lands in its output, and the qualified key
            # is what tells an operator which floe's check failed. Slashes are
            # legal in it; they are what makes it readable.
            inherit name;
            inherit (check) timeout expect reject;
          }
        ) checks
      );

      # `cata lab verify` reads a lab, it does not change one. A check that
      # could mutate fails eval rather than being caught in review.
      mutating = verifyTypes.mutatingOperations steps;

      test = {
        apiVersion = "chainsaw.kyverno.io/v1alpha1";
        kind = "Test";
        metadata.name = lib.replaceStrings [ "." ] [ "-" ] "${labName}-${clusterName}";
        spec = {
          cluster = clusterName;
          namespace = "default";
          skipDelete = true;
          inherit steps;
        };
      };
    in
    if mutating != [ ] then
      throw ''
        cluster '${clusterName}': verify checks declare mutating operation(s): ${lib.concatStringsSep ", " mutating}.

        `cata lab verify` is run against labs someone cares about, so a check
        may only `assert` and `error`.
      ''
    else
      pkgs.runCommand "verify-${labName}-${clusterName}" { } ''
        mkdir -p $out/${clusterName}
        ${lib.optionalString (
          steps != [ ]
        ) "cp ${yamlUtil.toYamlFile "chainsaw-test" test} $out/${clusterName}/chainsaw-test.yaml"}
      '';
}
