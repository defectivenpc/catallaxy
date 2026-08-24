# Rule: a floe says what traffic it needs, or the default deny silently
# refuses it.
{
  lib,
  pkgs,
  floes,
  labs,
  cannotKnowItsTraffic,
}:

let
  allFloes = lib.attrNames floes;

  declaring = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: l:
        lib.concatLists (
          lib.mapAttrsToList (
            _: clusterCfg:
            lib.attrNames (
              lib.filterAttrs (
                _: f: (f.enable or false) && ((f.network or { }).declared or false)
              ) clusterCfg.floes
            )
          ) l.config.lab.clusters
        )
      ) labs
    )
  );

  missing = lib.subtractLists (declaring ++ cannotKnowItsTraffic) allFloes;
in
{
  # A floe nobody's example lab uses is still a floe someone downstream can
  # enable, and under a default-deny cluster a floe that never says what it
  # needs is a floe whose pods are refused the traffic they ask for.
  every-floe-declares-its-network = pkgs.runCommand "every-floe-declares-its-network" { } ''
    ${lib.optionalString (missing != [ ]) ''
      echo "these floes never say what traffic they need:" >&2
      ${lib.concatMapStringsSep "\n" (f: ''echo "  ${f}" >&2'') missing}
      echo "" >&2
      echo "Set network.declared on each, with whatever egress and" >&2
      echo "ingress it needs. A floe needing nothing beyond the defaults" >&2
      echo "still sets it, so that it reads as reviewed rather than as" >&2
      echo "overlooked." >&2
      echo "" >&2
      echo "A floe enabled by no lab is checked against nothing, so it must" >&2
      echo "be enabled somewhere before it counts as declaring. A floe whose" >&2
      echo "traffic only a lab can know goes in cannotKnowItsTraffic with a" >&2
      echo "reason." >&2
      exit 1
    ''}
    touch $out
  '';
}
