# One cluster: a set of instantiated floes, linked and elaborated.
#
# This is the seam between the two halves. Above it the module system merges
# partial configuration; below it the linker resolves signatures and the
# domain folds components into a cluster picture. The submodule does not
# reinterpret either — it links, elaborates, and lowers.
{
  lib,
  pkgs,
  catallaxy,
  cataCharts,
  k8sSpecs,
  floeSet,
  lab,
}:

let
  inherit (lib) mkOption types;

  coreKinds = (import ../../lib/kubernetes/types.nix { inherit lib; }).coreKinds;
in
types.submodule (
  { name, config, ... }:
  {
    options = {
      floes = mkOption {
        type = types.attrsOf types.raw;
        default = { };
        description = ''
          Instantiated floes, keyed by the name they link under. One of them
          must provide `KUBERNETES_CLUSTER`; the rest are what installs into
          it.

          Values are `.instantiate { ... }` results, not modules — a floe is
          an instance, and the linker resolves between instances.
        '';
      };

      colima = {
        enable = mkOption {
          type = types.bool;
          default = pkgs.stdenv.isDarwin;
          defaultText = lib.literalExpression "pkgs.stdenv.isDarwin";
          description = ''
            Run docker through a colima VM. A host fact rather than a cluster
            one, which is why it lives on the lab and not in the cluster floe.
          '';
        };
        profile = mkOption {
          type = types.str;
          default = "catallaxy";
          description = "Colima profile name.";
        };
        cpu = mkOption {
          type = types.ints.positive;
          default = 4;
          description = "vCPUs for the VM.";
        };
        memory = mkOption {
          type = types.ints.positive;
          default = 8;
          description = "GiB of RAM for the VM.";
        };
        disk = mkOption {
          type = types.ints.positive;
          default = 60;
          description = "GiB of disk for the VM.";
        };
      };

      waitTimeout = mkOption {
        type = types.str;
        default = "10m";
        description = "How long a bundle may take to reconcile before the apply gives up.";
      };

      assertions = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "Config-validity checks scoped to this cluster.";
      };

      link = mkOption {
        type = types.raw;
        internal = true;
        readOnly = true;
        description = "The link result: provides, out, graph, phases, wiring.";
      };

      out = mkOption {
        type = types.raw;
        internal = true;
        readOnly = true;
        description = "The elaborated cluster picture: bundles, waves, namespaces, and the rest.";
      };

      manifests = mkOption {
        type = types.package;
        internal = true;
        readOnly = true;
        description = "The rendered wave tree for this cluster.";
      };

      spec = mkOption {
        type = types.attrs;
        internal = true;
        readOnly = true;
        description = "`ClusterSpec` as the CLI parses it.";
      };
    };

    config = {
      link = catallaxy.floe.link {
        units = config.floes;
        policies = [
          catallaxy.policies.oneCluster
          catallaxy.policies.componentsTargetTheCluster
          catallaxy.policies.needsNameSiblings
          catallaxy.policies.backsNameOwnBundles
        ];
      };

      out = catallaxy.elaborateCluster {
        linkResult = config.link;
        inherit coreKinds;
      };

      manifests = catallaxy.renderCluster {
        inherit name;
        owner = lab.name;
        cluster = config.out;
        inherit (config) waitTimeout;
      };

      # `catallaxy.cluster` already tracks `ClusterSpec`'s field names, so
      # this is a merge rather than a translation: the floe answers what a
      # cluster knows about itself, and the lab adds what only a lab knows.
      spec =
        let
          descriptor = lib.head (lib.attrValues config.out.cluster);
        in
        {
          inherit (descriptor)
            name
            provisioner
            provider
            kubeContext
            kubernetes
            network
            ;

          labName = lab.name;

          deploy.strategy = "kapp";
          lifecycle = { };

          provisionerConfig = {
            # The cluster floe leaves `network` null: which docker network it
            # joins is a fact about what else is on the host, which is the
            # lab's business. `docker-network-create` makes this one first.
            k3d = descriptor.k3d // {
              network = lab.name;
            };

            docker = {
              clusterName = descriptor.k3d.clusterName;
              inherit (config) waitTimeout;
              colima = {
                inherit (config.colima)
                  enable
                  profile
                  cpu
                  memory
                  disk
                  ;
              };
            };

            # `talos` is deliberately absent rather than `{ }`. Its
            # `#[serde(default)]` is on the field, so an omitted key is fine
            # and an empty one fails on a missing `clusterName`.
          };

          # The CLI knows a floe only as a name and whether it is on. That is
          # the whole of `FloeSpec`, and the linker has already refused any
          # floe that should not be here.
          floes = lib.mapAttrs (_: _: { enable = true; }) config.floes;

          inherit (config.out) exposedHosts;
        };
    };
  }
)
