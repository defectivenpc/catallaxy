# A plan token is spelled once, in `lib/plan-tokens.nix`.
#
# A producer and a consumer have to agree on the exact string, and `wants`
# builds an `optional:` anchor that matches nothing *silently* — so a token
# written by hand is wrong until someone notices the ordering, not until the
# build fails. Three sites had drifted: two spelling a token the registry
# already declared, one inventing `mr-reconciled`, which the registry did not
# have at all.
#
# `modules/` and `floes/` only: those write plan steps. `lib/tests/` and
# `nix/checks/` name literals on purpose, because a test asserting on rendered
# output should say the string it expects.
{ lib, pkgs }:

let
  roots = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../modules
      ../../floes
    ];
  };

  # A token is `<scope>/…/<state>`. `cluster/crds` in `lib/charts.nix` is a
  # chart path and not one of these, which is part of why the scan is scoped.
  pattern = "\"(cluster|stack)/[^\"]+/[a-z-]+\"|\"(lab|host)/[a-z-]+(/[a-z-]+)?\"";
in
{
  plan-tokens = pkgs.runCommand "plan-tokens-tests" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
    cd ${roots}
    if hits=$(grep -rnoE ${lib.escapeShellArg pattern} . 2>/dev/null); then
      echo "$hits" | sed 's/^/  /' >&2
      echo "" >&2
      echo "A plan token is spelled once, in lib/plan-tokens.nix, and reached" >&2
      echo "through \`t.cluster <name>\`, \`t.stack <name>\` or \`t.lab\`." >&2
      echo "" >&2
      echo "Writing one by hand is not caught by the graph: \`wants\` builds an" >&2
      echo "\`optional:\` anchor, and one that matches nothing is silent." >&2
      exit 1
    fi
    echo "no plan-token literals under modules/ or floes/" > $out
  '';
}
