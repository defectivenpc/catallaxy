# The consumer template renders.
#
# `templates/consumer` is what `nix flake init -t .#consumer` copies, and
# `docs/book/src/start-here/your-own-lab.md` walks through it line by line. It
# is the only code in the tree that exercises the consumer surface — `mkFloes`
# on a floe directory outside `floes/`, and `mkLab` on a lab that mixes those
# floes with the built-in set.
#
# Its own flake cannot be evaluated here: it names `github:onepunchtech/catallaxy`
# as an input, which a check has no network to fetch. So the check does what
# that flake does, against this tree — if the template's `lab.nix` or its floe
# stops evaluating, this fails, and a scaffold that does not render is worse
# than none.
{
  lib,
  pkgs,
  mkLab,
  mkFloes,
}:

let
  myFloes = mkFloes (import ../../templates/consumer/floes);

  lab = mkLab {
    modules = [ (import ../../templates/consumer/lab.nix { inherit myFloes; }) ];
  };

  # The two the template's own flake names. Spelled here so renaming one
  # fails this check rather than a consumer's first `nix flake init`.
  named = {
    inherit (lab.config.lab.out) cliConfig package;
  };
in
{
  consumer-template = pkgs.runCommand "consumer-template" { } ''
    ln -s ${named.package} rendered
    echo "${lab.config.lab.name}: ${toString (lib.length (lib.attrNames lab.config.lab.clusters))} cluster, cliConfig ${named.cliConfig.labName}" > $out
  '';
}
