# Which labs the *billable* runner will stand up, pinned.
#
# The same discipline as `self-contained.nix` and for a sharper reason. That
# predicate collapsing would make CI run everything or nothing; this one
# collapsing would make `nix run .#e2e-cloud` create things in a real account
# for a lab nobody meant to point at one — or quietly stop covering the lab
# that is the whole point of having the runner.
#
# `mentions` pins a substring of the reason, so this fails when a lab becomes
# ineligible for a *different* reason than it used to be. A lab that stops
# being a cloud lab and a lab that is mid-migration are both ineligible and
# only one of them is a thing to finish.
{
  lib,
  pkgs,
  cloudE2eLabs,
}:

let
  # Every lab, not only the cloud ones. A lab that grows a cloud provider
  # should appear here by failing this check, which is what stops one
  # arriving in the billable matrix without anybody writing it down.
  expected = {
    # The lab the runner exists for: a DOKS cluster made by a state-based
    # apply, and the lab installing into it.
    "cloud" = {
      eligible = true;
      providers = [ "digitalocean" ];
      requiredEnv = [ "DIGITALOCEAN_TOKEN" ];
      mentions = [ ];
    };

    # Every floe rendered together, which now includes `doks`. It reaches an
    # account for the same reason and is eligible on the same terms.
    "every-floe" = {
      eligible = true;
      providers = [ "digitalocean" ];
      requiredEnv = [ "DIGITALOCEAN_TOKEN" ];
      mentions = [ ];
    };

    # No provider at all: what makes this one a cloud lab is an externally
    # provisioned cluster, which a Crossplane controller in `mgmt` reconciles
    # using whatever credential that controller holds. So there is nothing
    # for the runner to require in the environment, and the account it
    # reaches is the cluster's rather than the runner's.
    "provisions" = {
      eligible = true;
      providers = [ ];
      requiredEnv = [ ];
      mentions = [ ];
    };
  };

  # A lab reaching nothing is not "ineligible" — it is not a cloud lab, and
  # saying so is different from saying it failed. Those all carry the same
  # reason, so they are matched by shape rather than listed one by one; a new
  # local lab should not have to be added to a table about cloud runs.
  notCloud = "names no cloud provider and no externally provisioned cluster";

  actual = cloudE2eLabs;

  describe =
    name: a:
    "${name}: eligible=${lib.boolToString a.eligible} "
    + "providers=[${lib.concatStringsSep ", " a.providers}] "
    + "env=[${lib.concatStringsSep ", " a.requiredEnv}] "
    + "reasons=${builtins.toJSON a.reasons}";

  mismatches = lib.concatLists (
    lib.mapAttrsToList (
      name: a:
      let
        want = expected.${name} or null;
        isLocal = lib.any (r: lib.hasInfix notCloud r) a.reasons;
      in
      if want == null then
        # Not in the table. Fine only if it says it is not a cloud lab —
        # otherwise something grew a provider and nobody wrote it down.
        lib.optional (!isLocal) "${describe name a} is not in the table and does not say it is a local lab"
      else
        lib.optional (a.eligible != want.eligible) (
          describe name a + " but the table expects eligible=${lib.boolToString want.eligible}"
        )
        ++ lib.optional (a.providers != want.providers) (
          describe name a + " but the table expects providers=[${lib.concatStringsSep ", " want.providers}]"
        )
        ++ lib.optional (a.requiredEnv != want.requiredEnv) (
          describe name a + " but the table expects env=[${lib.concatStringsSep ", " want.requiredEnv}]"
        )
        ++ lib.concatMap (
          m: lib.optional (!lib.any (r: lib.hasInfix m r) a.reasons) "${name}: no reason mentions '${m}'"
        ) want.mentions
    ) actual
  );

  # The other direction: a line naming a lab that no longer exists.
  stale = lib.mapAttrsToList (name: _: "${name} is in the table and is not a lab") (
    lib.filterAttrs (name: _: !(actual ? ${name})) expected
  );

  # And the control. Without it every assertion above could pass because
  # `cloudE2eLabs` came back empty — which is exactly how five refusals in
  # `nix/checks/secret-sharing.nix` once passed while checking nothing.
  noLabs = lib.optional (actual == { }) "cloudE2eLabs is empty, so this check compared nothing";

  findings = mismatches ++ stale ++ noLabs;
in
{
  cloud-e2e = pkgs.runCommand "cloud-e2e-tests" { } ''
    ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
    ${lib.optionalString (findings != [ ]) ''
      echo "" >&2
      echo "nix/checks/cloud-e2e.nix records which labs \`nix run .#e2e-cloud\`" >&2
      echo "will create things in a real account for, and what it demands be set" >&2
      echo "first. If this change is intended, update the table there." >&2
      exit 1
    ''}
    touch $out
  '';
}
