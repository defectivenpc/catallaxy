# The address plan, written down.
#
# RFC 0005 §5 says an address plan is a decision and must be written once. This
# is where it is written. `lib/allocation.nix` derives it from the lab's name;
# this records the result, and `checks.allocations` refuses a tree where the
# two disagree.
#
# That is what keeps the derivation honest. A lab renamed is a lab reallocated,
# and without this the move would be silent — which is the one thing §5's
# reason could not tolerate. Here it is a line in a reviewed diff.
{
  lib,
  pkgs,
  labDefs,
}:

let
  alloc = import ../lib/allocation.nix { inherit lib; };

  table = lib.mapAttrs (
    labName: lab:
    {
      slot = alloc.slotOf labName;
    }
    // {
      inherit (lab.config.lab.network) subnet;
      egress = lab.config.lab.egress.port;
      registry = lab.config.lab.registry.port;
      dns = lab.config.lab.dns.hostPort;
      proxyHttp = lab.config.lab.proxy.httpPort;
      proxyHttps = lab.config.lab.proxy.httpsPort;
    }
  ) labDefs;
in
pkgs.runCommand "allocations" { } ''
  mkdir -p $out
  cp ${pkgs.writeText "allocations.json" (builtins.toJSON table)} $out/allocations.json
  ${pkgs.jq}/bin/jq -S . $out/allocations.json > $out/sorted.json
  mv $out/sorted.json $out/allocations.json
''
