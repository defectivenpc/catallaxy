{
  lib,
  pkgs,
  floeCore,

  k8sApi,
}:

let
  floe = import ./authoring/prelude.nix { inherit lib floeCore; };

  inherit (import ./authoring/frame.nix { inherit lib floe; }) mkFramedFloe;

  sigs = import ./domain/sigs.nix { inherit lib floe; };

  kinds = import ./domain/kinds.nix {
    inherit
      lib
      floe
      k8sApi
      sigs
      ;
  };
  policies = import ./domain/policies.nix { inherit lib sigs; };

  distribution = floe.mkDistribution {
    name = "catallaxy";

    kinds = lib.filterAttrs (_: k: (k.__floeSig or false)) kinds;

    document = import ../document/generated.nix { T = floe.T; };
  };

in
rec {
  inherit
    floe
    kinds
    sigs
    policies
    ;

  floeInstance = lib.types.raw // {
    name = "floeInstance";
    description = "an instantiated floe";
    descriptionClass = "noun";
    check = v: builtins.isAttrs v && (v.__floeInstance or false);
  };

  provisionerUnitFor = clusterName: "${clusterName}-provisioner";

  hostContainerFor = labName: role: "catallaxy-${labName}-${role}";

  inherit (import ../allocation.nix { inherit lib; }) allocationFor;

  mkLabFloeWith =
    { floes, placeCluster }:
    import ./authoring/lab-floe.nix {
      inherit
        lib
        floe
        sigs
        floes
        placeCluster
        provisionerUnitFor
        labPolicies
        allocationFor
        ;
    };

  clusterOfProvisionerUnit = lib.removeSuffix "-provisioner";

  cdArrangementOf =
    link:
    let
      emitted = lib.attrValues (link.out."catallaxy.cd" or { });
    in
    if emitted == [ ] then
      {
        bootstrap = "kubectl-ssa";
        git = { };
        rootApplication = { };
        perCluster = { };
      }
    else
      lib.head emitted;

  clusterSecurityInputs = {
    podSecurity = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Label every namespace this cluster creates for Pod Security
              Admission.

              Off by default because turning it on can refuse a workload that
              was running, and that refusal should be somebody's decision. It
              costs nothing to run: PSA is in the API server, so unlike a
              NetworkPolicy it needs no CNI support and is enforced
              identically on k3d and on a cloud cluster.
            '';
          };

          enforce = lib.mkOption {
            type = lib.types.enum [
              "privileged"
              "baseline"
              "restricted"
            ];
            default = "baseline";
            description = ''
              The level the API server refuses pods below.

              `baseline` blocks the known privilege escalations and admits
              most upstream charts unchanged. `restricted` additionally
              requires non-root, a seccomp profile and dropped capabilities,
              which many charts need values changes to satisfy.
            '';
          };

          warn = lib.mkOption {
            type = lib.types.enum [
              "privileged"
              "baseline"
              "restricted"
            ];
            default = "restricted";
            description = ''
              The level a violation is warned about at, without being refused.

              Defaulted stricter than `enforce` on purpose: the warnings are
              what tells you whether raising `enforce` would break anything,
              and they cost nothing until you read them.
            '';
          };

          override = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.enum [
                "privileged"
                "baseline"
                "restricted"
              ]
            );
            default = { };
            example = {
              cilium = "privileged";
              podinfo = "restricted";
            };
            description = ''
              Namespaces that enforce a level other than `enforce`, keyed by
              namespace. It reads in both directions.

              Down, because a CNI or a storage driver genuinely needs host
              access, and the alternative is turning the whole cluster down to
              the level its most privileged component needs. Up, because a
              workload that already satisfies `restricted` should be held to
              it rather than to the cluster default.
            '';
          };
        };
      };
      default = { };
      description = "Pod Security Admission, over every namespace in this cluster.";
    };

    defaultDenyNamespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "podinfo" ];
      description = ''
        Namespaces that deny all traffic except what a policy allows. DNS to
        kube-system is excepted, because a namespace whose pods cannot resolve
        turns every failure into a name error.

        A list rather than a flag, and not the whole cluster: a NetworkPolicy
        is additive, so denying a namespace means every floe installing into
        it must declare the traffic it needs. No floe declares any today.
        Naming one namespace at a time is what makes that a decision per
        namespace instead of an outage.

        Refused on a cluster whose CNI does not enforce policy: the policies
        would apply, report healthy, and deny nothing.
      '';
    };
  };

  mkClusterFloe = mkFramedFloe clusterFrame;

  clusterFrame = {
    baseInputs = clusterSecurityInputs;
    policies = clusterPolicies;
  };

  inherit k8sApi;

  inherit (distribution) conformDocument;

  clusterPolicies = [
    policies.oneDelivery
    policies.needsNameSiblings
    policies.backsNameOwnBundles
    policies.kanidmPrincipalsAreUnique
    policies.providersVerifyWhatTheyPromise
    policies.promisedHostsAreRouted
  ];

  labPolicies = [
    policies.componentsTargetTheCluster
  ];

  planTokens = import ../plan-tokens.nix { inherit lib; };
  inherit (import ../eval/anchors.nix { }) needs wants;

  inherit (import ../lower/elaborate.nix { inherit lib floe k8sApi; }) elaborateCluster;
  inherit (import ../lower/slice.nix { inherit lib; }) sliceFor;
  inherit (import ../lower/render.nix { inherit lib pkgs; }) renderCluster;
}
