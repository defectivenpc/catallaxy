{
  lib,
  catallaxy,
  floes,
  catalogue,
}:

let
  inherit (import ./lower/cluster.nix { inherit lib catallaxy; })
    placeCluster
    lowerCluster
    ;
in
{
  mkCluster =
    {
      name,
      floe,
      provisioner,
    }:
    let
      placed = placeCluster {
        clusterName = name;
        labName = name;
        inherit floe provisioner;
      };

      link = catallaxy.floe.link {
        units = {
          ${name} = placed.clusterFloe;
          ${catallaxy.provisionerUnitFor name} = placed.provisioner;

          delivery = floes.lab-delivery { };
        };
        inherit catalogue;
      };

      lowered = lowerCluster {
        clusterName = name;
        inherit placed;

        lab = {
          inherit name link;
          hasIngress = false;
          cdArrangement = catallaxy.cdArrangementOf link;
        };
      };

      failed = builtins.filter (a: !a.assertion) lowered.assertions;
    in
    lib.throwIf (failed != [ ]) (
      "cluster '${name}' has failed assertions:\n"
      + lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed
    ) (placed // lowered);
}
