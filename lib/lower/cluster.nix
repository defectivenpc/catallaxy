# Lowering one cluster: an authored floe, its claim, and the document the pair
# makes.
#
# A plain function, because there is nothing here to merge. It places the
# claim, binds the cluster's hole to it, elaborates, renders, and folds the
# result into `ClusterSpec`. Every input is handed in and every output is
# returned; nothing reads an option tree.
#
# It was `modules/lab/cluster/default.nix`, a submodule — and the submodule had
# two callers both building its input by hand, `lib/lab.nix` synthesising a
# whole `lab` record to evaluate exactly one of them. That is a function
# pretending to be a submodule. The authoring surface it carried stays a
# submodule; this is the half below it.
#
# Before this it *synthesized* the cluster's floe: `requires` scanned off
# whatever was in a bag of instances, `provides` assembled from a table of
# crossable signatures plus a hardcoded list of what the lab reads. A floe's
# interface has to be readable from its header before anything evaluates, and
# a synthesized one is readable only after — which is the single property floes
# exist to provide, given up by the thing holding them. ADR 0003.
{
  lib,
  catallaxy,
}:

let
  coreKinds = (import ../kubernetes/types.nix { inherit lib; }).coreKinds;
  infraLib = import ../render/infra.nix { inherit lib; };
in
{
  # lowerCluster :: { clusterName; floe; claim; lab; } -> lowered
  #
  # `lab` is what a cluster may read of the lab around it: its name, whether
  # the lab fronts it, the one link, and the delivery arrangement
  # folded from what every cluster said. Not the whole lab, so that the list
  # is visible — every one of these is a coupling, and a cluster authored on
  # its own has to be handed an answer for each.
  #
  # Returns the placed `claim` as well as the lowering, because the lab links
  # the placed instance and the placement happens here.
  # placeCluster :: { clusterName; floe; claim; labName; } -> { claim; clusterFloe; security; }
  #
  # The half that happens *before* linking, and the reason it is its own
  # function: the lab floe's `units` are what gets linked, so the claim has to
  # be placed and the cluster's hole bound to it while there is still no link
  # to read. Everything here comes off the two declarations and the lab's name.
  #
  # It was the top of `lowerCluster`, and that it was one function with the
  # lowering was the module system's laziness hiding two phases: the submodule
  # produced `placedClaim` and `spec` from one call, and the link that `spec`
  # needs is built out of `placedClaim`.
  placeCluster =
    {
      clusterName,
      floe,
      claim,
      labName,
    }:
    let
      claimUnit = catallaxy.claimUnitFor clusterName;

      placementDefaults = {
        name = clusterName;
        instanceName = "${lib.replaceStrings [ "." ] [ "-" ] labName}-${clusterName}";

        network = labName;
      };

      placedClaim =
        (claim.def.instantiate (
          (lib.filterAttrs (k: _: claim.def.inputs ? ${k}) placementDefaults) // claim.supplied
        )).bind
          claim.bindings;

      claimHoles = lib.attrNames (
        lib.filterAttrs (_: sig: sig.name == "KUBERNETES_CLUSTER") floe.def.requires
      );

      edgeHoles = lib.attrNames (lib.filterAttrs (_: sig: sig.name == "CLUSTER_EDGE") floe.def.optional);

      clusterFloe =
        if claimHoles == [ ] then
          throw (
            "cluster '${clusterName}': its floe '${floe.def.name}' does not require "
            + "KUBERNETES_CLUSTER, so there is no claim for `lab.clusters.${clusterName}.claim` "
            + "to answer. A cluster floe leaves its claim open: add "
            + "`requires.claim = sigs.KUBERNETES_CLUSTER` to it, and let the components "
            + "inside resolve against that."
          )
        else
          floe.bind (lib.genAttrs (claimHoles ++ edgeHoles) (_: claimUnit));

    in
    {
      claim = placedClaim;
      inherit clusterFloe;

      security = floe.inputsChecked;
    };

  # lowerCluster :: { clusterName; placed; lab; } -> lowered
  #
  # The half that happens *after* linking. `placed` is what `placeCluster`
  # returned, and `lab.link` is the one resolution every cluster is a view of.
  #
  # `lab` is what a cluster may read of the lab around it: its name, whether
  # the lab fronts it, the one link, and the delivery arrangement folded from
  # what every cluster said. Not the whole lab, so that the list is visible —
  # every one of these is a coupling, and a cluster authored on its own has to
  # be handed an answer for each.
  lowerCluster =
    {
      clusterName,
      placed,
      lab,
    }:
    let
      claimUnit = catallaxy.claimUnitFor clusterName;
      inherit (placed) security;

      link = catallaxy.sliceFor {
        inherit clusterName;
        claimFrom = claimUnit;
      } lab.link;

      out = catallaxy.elaborateCluster {
        linkResult = link;
        inherit coreKinds;
      };

      namespaceLabels =
        let
          psa = security.podSecurity;
          levelFor = ns: psa.override.${ns} or psa.enforce;
        in
        lib.optionalAttrs psa.enable (
          lib.genAttrs out.namespaces (ns: {
            "pod-security.kubernetes.io/enforce" = levelFor ns;
            "pod-security.kubernetes.io/warn" = psa.warn;
          })
        );

      namespaceResources = map (
        ns: catallaxy.kinds.mkDefaultDeny { namespace = ns; }
      ) security.defaultDenyNamespaces;

      descriptor = lib.head (lib.attrValues out.cluster);

      policyAssertions =
        let
          k3d = descriptor.config.k3d or null;
          enforces = k3d == null || k3d.noFlannel;
          asked = security.defaultDenyNamespaces;
        in
        lib.optional (asked != [ ] && !enforces) {
          assertion = false;
          message =
            "defaultDenyNamespaces names ${toString (lib.length asked)} "
            + "namespace(s) (${lib.concatStringsSep ", " asked}), but this cluster runs k3d's default "
            + "Flannel, which has no policy engine. The policies would apply, report healthy, "
            + "and deny nothing. Put a CNI that enforces them in the cluster — the `cilium` "
            + "floe — and export its `CNI_BOOTSTRAP` so the claim starts without Flannel.";
        };

      manifests = catallaxy.renderCluster {
        name = clusterName;
        owner = lab.name;
        cluster = out;

        inherit namespaceLabels namespaceResources;
      };

      provisioner = lib.head (lib.attrNames descriptor.config);

      labKnows = {
        talos =
          c:
          c
          // {
            reachableFrom = lib.optional lab.hasIngress (catallaxy.hostContainerFor lab.name "ingress");
          };

        external = c: removeAttrs c [ "kubeconfigFrom" ];
      };
    in
    {
      inherit
        link
        out
        manifests
        ;

      stacks = infraLib.collectStacks {
        scope = clusterName;
        inherit (out) resources publications;
      };

      assertions = out.assertions ++ policyAssertions;
      inherit (out) warnings;

      spec = {
        claim = {
          inherit (descriptor)
            name
            instanceName
            kubernetes
            network
            ;
          context = descriptor.kubeContext;
        };

        provisioning = {
          config = {
            ${provisioner} = (labKnows.${provisioner} or lib.id) descriptor.config.${provisioner};
          };

          hooks = [ ];

          inherit (descriptor) wait;
        };

        content = {
          tree = "${manifests}";

          inherit (out) namespaces exposedHosts;

          waves = map (
            wave:
            map (b: {
              inherit (b) name hasReadyProbe resourceCount;
            }) wave
          ) out.waves;

          inherit (out) projections;
        };

        delivery = lab.cdArrangement.perCluster.${clusterName};
      };
    };
}
