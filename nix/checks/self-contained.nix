# Which labs the e2e runner will stand up, pinned.
#
# `lab.out.selfContained` is derived, which is what makes it useful — a lab
# that grows a sops store leaves the matrix on its own. It is also what makes
# it dangerous: the predicate could collapse to "everything is eligible" or
# "nothing is" and CI would go on reporting green, having run everything or
# nothing.
#
# So the expectation is written out here and compared in both directions: a lab
# added without a line below fails, and a line naming a lab that no longer
# exists fails too.
#
# `mentions` is the important half. A reason is prose and prose gets reworded;
# pinning a substring means this fails when a lab becomes ineligible for a
# *different* reason than it used to be, which is the change worth catching.
{
  lib,
  pkgs,
  e2eLabs,
}:

let
  expected = {
    "minimal.local" = {
      eligible = true;
      mentions = [ ];
    };
    "minimal.tls" = {
      eligible = true;
      mentions = [ ];
    };

    # Env-backed, and it names the file that sets them, so it stands up
    # unattended. Remove `lab.secrets.envFile` and it becomes ineligible with
    # a reason mentioning that option.
    "minimal.secrets" = {
      eligible = true;
      mentions = [ ];
    };

    # The gitops lab: `cata` applies Argo CD and the git server, publishes the
    # rendered tree into that server, and hands the cluster over. Nothing in
    # it needs a human or a credential from outside, so it stands up
    # unattended like the rest.
    "gitops.local" = {
      eligible = true;
      mentions = [ ];
    };
  };

  known = lib.filter (n: e2eLabs ? ${n}) (lib.attrNames expected);

  # Every way the two can disagree, each reported separately, so a failure
  # names the shape of the problem rather than just its existence.
  problems =
    map (n: "${n} is a lab and nothing here expects it") (
      lib.subtractLists (lib.attrNames expected) (lib.attrNames e2eLabs)
    )
    ++ map (n: "${n} is expected here and is not a lab") (
      lib.subtractLists (lib.attrNames e2eLabs) (lib.attrNames expected)
    )
    ++ map (
      n:
      "${n}: expected eligible=${lib.boolToString expected.${n}.eligible}, got "
      + "${lib.boolToString e2eLabs.${n}.eligible} (${lib.concatStringsSep "; " e2eLabs.${n}.reasons})"
    ) (lib.filter (n: e2eLabs.${n}.eligible != expected.${n}.eligible) known)

    # Eligible means nothing stands in the way, so there is nothing to say.
    ++ map (n: "${n} is eligible but still gives reasons") (
      lib.filter (n: e2eLabs.${n}.eligible && e2eLabs.${n}.reasons != [ ]) known
    )

    # The failure this exists for: a lab dropping out of the matrix with
    # nothing to print about why.
    ++ map (n: "${n} is ineligible and says nothing about why") (
      lib.filter (n: !e2eLabs.${n}.eligible && e2eLabs.${n}.reasons == [ ]) known
    )

    # A reason that stopped mentioning what it used to is a check that stopped
    # catching what it used to.
    ++ lib.concatMap (
      n:
      let
        joined = lib.concatStringsSep " " e2eLabs.${n}.reasons;
      in
      map (m: "${n}: no reason mentions '${m}'") (
        lib.filter (m: !(lib.hasInfix m joined)) expected.${n}.mentions
      )
    ) known;
in
{
  self-contained = pkgs.runCommand "self-contained-tests" { } ''
    ${lib.concatMapStringsSep "\n" (p: "echo ${lib.escapeShellArg p} >&2") problems}
    ${lib.optionalString (problems != [ ]) ''
      echo "" >&2
      echo "nix/checks/self-contained.nix records which labs the e2e runner stands up." >&2
      echo "If this change is intended, update the table there — it is the only" >&2
      echo "thing stopping the eligibility predicate from quietly collapsing." >&2
      exit 1
    ''}
    touch $out
  '';
}
