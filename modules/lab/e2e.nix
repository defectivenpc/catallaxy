# Whether this lab can be stood up start to finish on a machine with nothing
# but docker on it.
#
# Derived rather than declared, which is the whole point: a lab that grows a
# cloud cluster or a sops store leaves the e2e set on its own, and one that
# loses them rejoins it. CI reads this to build its matrix, so a hand-written
# list would be a second place to forget.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  # Provisioners shown to complete a lab unattended. Deliberately narrower
  # than "needs no cloud account": the gate is about what has been proven, not
  # what looks local.
  #
  # Talos took three things k3d gave for free, and they are worth keeping
  # written down for whoever migrates it: its nodes sit on a network talosctl
  # makes and will not let anything join, so the lab's proxy reaches into that
  # network rather than the cluster joining the lab's; k3s's ServiceLB binds 80
  # and 443 on the node, so the gateway there is a NodePort the lab pins and
  # the proxy dials; and a Gateway with no address to assign never publishes
  # one, so it is waited on by `Programmed` instead.
  provenUnattended = [
    "k3d"
    "talos"
  ];

  clusters = config.lab.clusters;

  unproven = lib.attrNames (
    lib.filterAttrs (_: c: !(builtins.elem c.spec.provisioner provenUnattended)) clusters
  );

  backendOf = storeName: config.lab.secrets.stores.${storeName}.backend or "sops";

  # A store only opens with no credentials on the machine when its backend is
  # `env`. Everything else wants a key, a token or a running server.
  storedOutsideEnv = lib.mapAttrsToList (
    secretName: secret: "${secretName} in store ${secret.store}, backend ${backendOf secret.store}"
  ) (lib.filterAttrs (_: secret: backendOf secret.store != "env") config.lab.secrets.managed);

  envSecretsWithNoFile = lib.optionals (config.lab.secrets.envFile == null) (
    lib.attrNames (
      lib.filterAttrs (_: secret: backendOf secret.store == "env") config.lab.secrets.managed
    )
  );

  quote = lib.concatStringsSep ", ";

  # Read off both plans, not just the deployment one: a lab whose *teardown*
  # needs a human is no more runnable unattended than one whose deployment
  # does, and it is the worse of the two — the failure leaves the lab up.
  interactiveSteps = map (step: "${step.name} (${step.origin})") (
    lib.filter (step: step.policy.interactive) (
      config.lab.out.deploymentPlan ++ config.lab.out.teardownPlan
    )
  );

  # One parked reason is still not computable and is deliberately absent
  # rather than stubbed: a cluster that `provisions` others, for which there
  # is no option yet. It comes back with the feature that introduces it, and
  # until then no lab can trip it.
  reasons =
    lib.optional (clusters == { }) "the lab declares no clusters"
    ++ lib.optional (unproven != [ ]) (
      "${quote unproven} uses a provisioner CI has not been shown to complete a lab on unattended"
    )
    ++ lib.optional (storedOutsideEnv != [ ]) (
      "these live in a store nothing here can open: ${quote storedOutsideEnv}, "
      + "and a store only opens with no credentials on the machine when its backend is \"env\""
    )
    ++ lib.optional (envSecretsWithNoFile != [ ]) (
      "${quote envSecretsWithNoFile} take their values from the environment, and the lab names no "
      + "file that sets them, so point lab.secrets.envFile at one, as a path relative to the flake root"
    )
    ++ lib.optional (interactiveSteps != [ ]) (
      "${quote interactiveSteps} needs someone at the terminal, and an unattended run has nobody to "
      + "answer it, so the step will time out rather than fail fast"
    );
in
{
  options.lab.out.selfContained = mkOption {
    readOnly = true;
    internal = true;
    type = types.submodule {
      options = {
        eligible = mkOption {
          type = types.bool;
          description = "True when nothing stands between this lab and a machine with docker on it.";
        };
        reasons = mkOption {
          type = types.listOf types.str;
          description = "What does stand in the way, one sentence each. Empty exactly when `eligible`.";
        };
        envFile = mkOption {
          type = types.nullOr types.str;
          description = ''
            File the runner loads before the lab starts, relative to the flake
            root. Null when the lab needs nothing from the environment.
          '';
        };
      };
    };
    description = ''
      Whether this lab can be stood up start to finish on one machine with
      nothing but docker, and if not, why.

      `reasons` is empty exactly when `eligible` is true, and is what the
      runner prints for a lab it skipped — so a lab that drops out of the
      matrix says so itself rather than quietly vanishing from a list.
    '';
  };

  config.lab.out.selfContained = {
    eligible = reasons == [ ];
    inherit reasons;
    inherit (config.lab.secrets) envFile;
  };
}
