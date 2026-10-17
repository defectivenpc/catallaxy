# The Catallaxy distribution over floe core: the output kinds it registers,
# the signatures its floes speak, the policies it enforces at link, the fold
# from a link result to a cluster picture, and the renderer over that.
{
  lib,
  pkgs,
  floeCore,

  # API group -> generated type file, from `lib/floe-crds.nix`. Handed in because
  # the types live beside the floes that install the CRDs, and a floe depends
  # on this distribution rather than the reverse — so the one thing that would
  # be a cycle arrives as an argument instead.
  k8sApi,
}:

let
  # Core plus this domain's own types; see ./authoring/prelude.nix.
  floe = import ./authoring/prelude.nix { inherit lib floeCore; };

  inherit (import ./authoring/frame.nix { inherit lib floe; }) mkFramedFloe;

  sigs = import ./domain/sigs.nix { inherit floe; };

  kinds = import ./domain/kinds.nix {
    inherit
      lib
      floe
      k8sApi
      sigs
      ;
  };
  policies = import ./domain/policies.nix { inherit lib sigs; };

  # What this distribution owns: the kinds a floe may emit, and the shape they
  # fold into. The document's type is generated from the Rust types `cata`
  # parses it into, so those are the one definition of it.
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

  # The option type for a floe instance.
  #
  # `types.raw` with a check. Raw is what an instance needs — it is an opaque
  # attrset the module system must not merge or recurse into — and the check
  # is what raw gives up: a definition that is not an instance used to reach
  # the linker, which said "unit 'x' is not an instantiated floe" about a
  # unit name rather than about the option holding the wrong value. The
  # commonest way to get there is passing a floe *definition* where an
  # instance was wanted, which is one missing `{ }`.
  floeInstance = lib.types.raw // {
    name = "floeInstance";
    description = "an instantiated floe";
    descriptionClass = "noun";
    check = v: builtins.isAttrs v && (v.__floeInstance or false);
  };

  # provisionerUnitFor :: ClusterName -> UnitName
  #
  # The lab unit a cluster's provisioner is linked under. A cluster floe leaves
  # `KUBERNETES_CLUSTER` open and the provisioner answering it sits beside it,
  # so the provisioner is its own unit and needs its own name.
  #
  # Derived rather than written, because the deployer already said which
  # cluster a provisioner is for by writing it under that cluster. Here rather than
  # at the three call sites — the submodule that binds the hole, the lab that
  # builds the link, and the planner that reads the wiring off it — because a
  # name three places construct is a name three places can disagree about.
  provisionerUnitFor = clusterName: "${clusterName}-provisioner";

  # hostContainerFor :: LabName -> Role -> ContainerName
  #
  # What a host floe's container is called. Every one of them is
  # `catallaxy-<lab>-<role>`, and the lab's name arrives on `LAB_NETWORK` — so
  # a host floe names its own container rather than being handed the string.
  #
  # It was four `lab.<service>.containerName` options with four interpolated
  # defaults and four `defaultText` blocks restating them, which is one
  # convention written eight times. `cata` reads the name off the service
  # record, so this is the only place it is decided.
  hostContainerFor = labName: role: "catallaxy-${labName}-${role}";

  # What each lab is allocated on the host it shares: one subnet and five host
  # ports, from the lab's name. Re-exported here because the floes that publish
  # those ports are the ones that should decide them, and a floe reaches
  # `lib/` only through this.
  inherit (import ../allocation.nix { inherit lib; }) allocationFor;

  # What a lab's own floe is built with — `mkClusterFloe` one level up.
  #
  # Partially applied, because the two things it still needs are the two this
  # file cannot see: the floe *set*, which `lib/lab.nix` builds out of these
  # definitions, and `placeCluster`, whose module takes the whole distribution.
  # `lib/lab.nix` has both and finishes the application.
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

  # clusterOfProvisionerUnit :: UnitName -> ClusterName
  #
  # The inverse, for a lab-scope floe that needs the cluster names and has only
  # a collection to get them from. `KUBERNETES_CLUSTER` is provided by exactly
  # three floes and all three are claims, so a collection of it is keyed by
  # `<cluster>-provisioner` and this is what reads the cluster out.
  #
  # Here rather than a `removeSuffix` at the call site, because the convention
  # is one decision and a floe inverting it by hand would be a second place it
  # is written down. A cluster actually named `x-provisioner` is fine — its unit is
  # `x-provisioner-provisioner` — and a lab unit colliding with a provisioner's name is refused
  # by `modules/lab/link.nix` before this is read.
  clusterOfProvisionerUnit = lib.removeSuffix "-provisioner";

  # cdArrangementOf :: linkResult -> { bootstrap; git; rootApplication; perCluster; }
  #
  # The one `catallaxy.cd` a link produced, folded. `lab-delivery` is a
  # singleton, so there is one answer or none; none is a link with no applier
  # at all, which `policies.oneDelivery` refuses per cluster before anything
  # reads this, and the empty arrangement is what a link with no clusters
  # yields.
  #
  # Here rather than at the two call sites for the same reason `provisionerUnitFor`
  # is: `modules/lab/link.nix` folds it for a lab and `lib/cluster.nix` for a
  # standalone cluster, and a default two places write is a default two places
  # can disagree about.
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

  # What a cluster asks of every namespace in it.
  #
  # Pod Security Admission labels and a default-deny NetworkPolicy: the two
  # controls that are about the namespaces a cluster's floes create rather
  # than about any one floe. A component floe declaring either would be
  # declaring it about its neighbours' namespaces — which is why these are the
  # cluster's to say, and why they are inputs of the cluster floe rather than
  # options on a submodule beside it.
  #
  # Inputs and not a hole: there is nothing to resolve. They are what a
  # deployer decides about this cluster, and `inputsChecked` is readable off
  # the instance before the link runs, which is what lets the lowering apply
  # them where the namespaces are made.
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

  # mkClusterFloe :: mkFloe-args -> callable floe definition
  #
  # What a lab's own cluster floes are built with: the cluster frame, and
  # nothing else. A frame is the inputs every floe of a kind has and the
  # policies it is held to — here the two controls over a cluster's namespaces,
  # because every cluster has namespaces, and the list of questions whose
  # subject is a cluster's units. Both are things every cluster wanted and
  # neither is something `mkFloe` should know about.
  #
  # An author may refine a framed input rather than redeclare it, and a name
  # the frame does not declare is an ordinary new input. `lib/floe-catallaxy/authoring/frame.nix`.
  mkClusterFloe = mkFramedFloe clusterFrame;

  clusterFrame = {
    baseInputs = clusterSecurityInputs;
    policies = clusterPolicies;
  };

  # What every cluster floe in this distribution checks of its own units.
  #
  # A list rather than a default, because `mkFloe` has no notion of a cluster
  # and should not: these are statements about one cluster's units, and an
  # author writes `policies = catallaxy.clusterPolicies;` the way they write
  # `requires.cluster = sigs.KUBERNETES_CLUSTER`. Adding one here adds it to
  # every cluster, which is the point — the alternative was a list copied into
  # thirteen cluster floes.
  #
  # Two are not here. `oneCluster` counted the cluster descriptors a link
  # produced, and a cluster declaring `requires.cluster` gets zero and two
  # refused by resolution instead, naming the hole.
  #
  # `componentsTargetTheCluster` moved to `labPolicies`, because a cluster's
  # claim is a unit *beside* it now: inside the cluster the claim arrives as
  # an injected unit, and the linker drops edges to those because the value is
  # the parent's — so asked here the question has no cluster to find. The
  # policy's own note said where the true statement lives: "the statement one
  # level up is the true one". ADR 0003.
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

  # What the *lab's* link checks, which is every question whose subject is a
  # cluster and the thing that establishes it. One level up from
  # `clusterPolicies`, and the level at which a claim is an ordinary unit.
  labPolicies = [
    policies.componentsTargetTheCluster
  ];

  # The plan's vocabulary, so a floe declaring a step reaches a token rather
  # than writing one. A token spelled by hand is not caught by the graph —
  # `wants` builds an `optional:` anchor and one that matches nothing is
  # silent — which is why `plan-tokens` refuses the literal, and why a host
  # floe with steps of its own needs this exported.
  planTokens = import ../plan-tokens.nix { inherit lib; };
  inherit (import ../eval/anchors.nix { }) needs wants;

  inherit (import ../lower/elaborate.nix { inherit lib floe k8sApi; }) elaborateCluster;
  inherit (import ../lower/slice.nix { inherit lib; }) sliceFor;
  inherit (import ../lower/render.nix { inherit lib pkgs; }) renderCluster;
}
