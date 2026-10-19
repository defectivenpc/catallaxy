{
  lib,
  catallaxy,
}:

let
  inherit (catallaxy.k8sApi) coreKinds;
  infraLib = import ../render/infra.nix { inherit lib; };
in
{
  placeCluster =
    {
      clusterName,
      floe,
      provisioner,
      labName,
    }:
    let
      provisionerUnit = catallaxy.provisionerUnitFor clusterName;

      placementDefaults = {
        name = clusterName;
        instanceName = "${lib.replaceStrings [ "." ] [ "-" ] labName}-${clusterName}";

        network = labName;
      };

      placedProvisioner =
        (provisioner.def.instantiate (
          (lib.filterAttrs (k: _: provisioner.def.inputs ? ${k}) placementDefaults) // provisioner.supplied
        )).bind
          provisioner.bindings;

      handleHoles = lib.attrNames (
        lib.filterAttrs (_: sig: sig.name == "KUBERNETES_CLUSTER") floe.def.requires
      );

      edgeHoles = lib.attrNames (lib.filterAttrs (_: sig: sig.name == "CLUSTER_EDGE") floe.def.optional);

      provisionerProvided =
        sigName: surface: lib.attrNames (lib.filterAttrs (_: sig: sig.name == sigName) surface);

      storageHoles =
        provisionerProvided "STORAGE_CLASS" floe.def.requires
        ++ provisionerProvided "STORAGE_CLASS" floe.def.optional;

      clusterFloe =
        if handleHoles == [ ] then
          throw (
            "cluster '${clusterName}': its floe '${floe.def.name}' does not require "
            + "KUBERNETES_CLUSTER, so there is no hole for `lab.clusters.${clusterName}.provisioner` "
            + "to answer. A cluster floe leaves its claim open: add "
            + "`requires.cluster = sigs.KUBERNETES_CLUSTER` to it, and let the components "
            + "inside resolve against that."
          )
        else
          floe.bind (lib.genAttrs (handleHoles ++ edgeHoles ++ storageHoles) (_: provisionerUnit));

    in
    {
      provisioner = placedProvisioner;
      inherit clusterFloe;

      security = floe.inputsChecked;
    };

  lowerCluster =
    {
      clusterName,
      placed,
      lab,
    }:
    let
      provisionerUnit = catallaxy.provisionerUnitFor clusterName;
      inherit (placed) security;

      link = catallaxy.sliceFor {
        inherit clusterName;
        provisionerFrom = provisionerUnit;
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

      policyEngines = lib.attrValues (link.out."catallaxy.networkPolicy" or { });

      policyAssertions =
        let
          enforces = policyEngines != [ ];
          asked = security.defaultDenyNamespaces;
        in
        lib.optional (asked != [ ] && !enforces) {
          assertion = false;
          message =
            "defaultDenyNamespaces names ${toString (lib.length asked)} "
            + "namespace(s) (${lib.concatStringsSep ", " asked}), but this cluster runs k3d's default "
            + "Flannel, which has no policy engine. The policies would apply, report healthy, "
            + "and deny nothing. Nothing in this cluster emits "
            + "`catallaxy.networkPolicy`, which is how a network implementation says it has an "
            + "engine. Put one in — the `cilium` floe — and export its `CNI_BOOTSTRAP` so the "
            + "provisioner starts without its own.";
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

        external =
          c:
          removeAttrs c [
            "kubeconfigFrom"
            "provisionedBy"
          ];
      };
    in
    {
      inherit
        link
        out
        manifests
        ;

      networkPolicy = {
        enabled = policyEngines != [ ] && security.defaultDenyNamespaces != [ ];
        implementations = map (p: p.implementation) policyEngines;
      };

      stacks = infraLib.collectStacks {
        scope = clusterName;
        inherit (out) resources publications;
      };

      assertions = out.assertions ++ policyAssertions;
      inherit (out) warnings;

      spec = {
        clusterHandle = {
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
