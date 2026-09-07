# Whether this lab can be stood up against a real cloud account, unattended.
#
# A sibling of `lab.out.selfContained`, not an extension of it, and the
# distinction is load-bearing. That predicate asks whether a lab runs "on a
# machine with nothing but docker on it", and a cloud lab genuinely does not —
# adding a cloud provisioner to `provenUnattended` would make the sentence
# false and put a billable lab into the matrix `nix flake check` drives.
#
# So there are two questions and two answers. `selfContained` gates the free
# runner that CI runs on every change; this gates one that spends money and
# runs when a human or a schedule asks.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  clusters = config.lab.clusters;

  # Every stack the lab's floes declare, and the providers they name.
  #
  # A lab with no stacks and no external clusters has nothing a cloud account
  # would add, so it is not "ineligible" — it is not a cloud lab at all, and
  # saying so is different from saying it failed a test.
  stacks = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: c: c.stacks) clusters);

  providers = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (_: s: lib.mapAttrsToList (_: r: r.provider) s.resources) stacks
    )
  );

  # Providers that reach nothing. A stack of only these is exercised by the
  # ordinary e2e runner and needs no account — which is the whole reason the
  # resources category is iterable without one.
  offline = [
    "local"
    "random"
    "null"
  ];

  cloudProviders = lib.subtractLists offline providers;

  externalClusters = lib.attrNames (
    lib.filterAttrs (_: c: c.spec.provisioner == "external") clusters
  );

  isCloudLab = cloudProviders != [ ] || externalClusters != [ ];

  # The variables an operator has to have set. Derived from the providers
  # rather than declared, so a lab that grows a second provider says so
  # itself instead of failing halfway through an apply on a missing token.
  #
  # Names are the providers' own, because that is what the provider reads and
  # a translation table would be a second place to be wrong.
  envForProvider = {
    digitalocean = [ "DIGITALOCEAN_TOKEN" ];
  };

  requiredEnv = lib.unique (
    lib.concatMap (
      p:
      envForProvider.${p}
        or (throw "lab.out.cloudE2e: no environment is recorded for provider '${p}'; add it to `envForProvider` in modules/lab/e2e-cloud.nix")
    ) cloudProviders
  );

  quote = lib.concatStringsSep ", ";

  # Interactive steps disqualify a cloud run for the same reason they
  # disqualify a local one, and worse: the failure leaves cloud resources up.
  interactiveSteps = map (step: "${step.name} (${step.origin})") (
    lib.filter (step: step.policy.interactive) (
      config.lab.out.deploymentPlan ++ config.lab.out.teardownPlan
    )
  );

  reasons =
    lib.optional (config.lab.unstable != null) (
      "this lab is mid-migration and is not expected to stand up: ${config.lab.unstable}"
    )
    ++ lib.optional (!isCloudLab) (
      "this lab names no cloud provider and no externally provisioned cluster, so there is "
      + "nothing here a cloud account would add — run it with `nix run .#e2e` instead"
    )
    ++ lib.optional (interactiveSteps != [ ]) (
      "${quote interactiveSteps} needs someone at the terminal, and an unattended run has "
      + "nobody to answer it — which for a cloud lab means the run times out with resources up"
    );
in
{
  options.lab.out.cloudE2e = mkOption {
    readOnly = true;
    internal = true;
    type = types.submodule {
      options = {
        eligible = mkOption {
          type = types.bool;
          description = "True when this lab can be stood up against a real account unattended.";
        };
        reasons = mkOption {
          type = types.listOf types.str;
          description = "What stands in the way, one sentence each. Empty exactly when `eligible`.";
        };
        requiredEnv = mkOption {
          type = types.listOf types.str;
          description = ''
            Variables the runner refuses to start without.

            Checked before anything is created rather than discovered by an
            apply: a missing token halfway through leaves whatever the first
            half made, and nothing that knows to clean it up.
          '';
        };
        providers = mkOption {
          type = types.listOf types.str;
          description = "Cloud providers this lab's stacks name. Empty for a lab that reaches nothing.";
        };
        tag = mkOption {
          type = types.str;
          description = ''
            The tag every object this lab creates carries.

            What makes a leak findable. A cluster nobody can list by lab is a
            cluster nobody notices is still running, and the reaper has
            nothing to go on.
          '';
        };
      };
    };
    description = ''
      Whether this lab can be stood up against a real cloud account, and if
      not, why.

      Deliberately a sibling of `selfContained` rather than a widening of it:
      that one asks whether a lab needs nothing but docker, which a cloud lab
      does not, and collapsing the two would put a billable lab into the
      matrix CI runs on every change.
    '';
  };

  config.lab.out.cloudE2e = {
    eligible = reasons == [ ];
    inherit reasons requiredEnv;
    providers = cloudProviders;
    tag = "catallaxy-lab-${config.lab.name}";
  };
}
