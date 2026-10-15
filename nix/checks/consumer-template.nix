# The consumer template renders.
#
# `templates/consumer` is what `nix flake init -t .#consumer` copies, and
# `docs/book/src/start-here/your-own-lab.md` walks through it line by line. It
# is the only code in the tree that exercises the consumer surface —
# `withFloes` on a floe directory outside `floes/`, and `mkLab` on a lab that
# mixes those floes with the built-in set.
#
# Its own flake cannot be evaluated here: it names `github:defectivenpc/catallaxy`
# as an input, which a check has no network to fetch. So the check does what
# that flake does, against this tree — if the template's `lab.nix` or its floe
# stops evaluating, this fails, and a scaffold that does not render is worse
# than none.
{
  lib,
  pkgs,
  withFloes,

  # What a consumer actually reaches through, so that a name the template
  # reads off it and nothing exposes fails here instead of at their first
  # `nix flake init`. The template's own flake cannot be evaluated in a check
  # — it names `github:defectivenpc/catallaxy` as an input — so until now the
  # only thing proving those names existed was that somebody tried it.
  exposed,
}:

let
  # Exactly what the template's flake does, including the rebuild: its floes'
  # CRD types have to reach the record its floes are defined against, and
  # taking `catallaxy` from anywhere else would be two records.
  cata = withFloes (import ../../templates/consumer/floes);

  lab = cata.mkLab (
    (import ../../templates/consumer/lab.nix {
      inherit lib;
      inherit (cata) catallaxy floes;
    })
      {
        name = "my-platform";
      }
  );

  # The two the template's own flake names. Spelled here so renaming one
  # fails this check rather than a consumer's first `nix flake init`.
  named = {
    inherit (lab) cliConfig package;
  };

  # Every `cata.<name>` and `inherit (cata) <name>` the template's flake
  # reads, against what `legacyPackages` actually has.
  flakeSrc = builtins.readFile ../../templates/consumer/flake.nix;

  wanted = lib.unique (
    map (m: lib.head m) (
      lib.filter (m: m != null) (
        map (l: builtins.match ".*cata\\.([a-zA-Z][A-Za-z0-9_]*).*" l) (lib.splitString "\n" flakeSrc)
      )
    )
    ++ lib.concatMap (
      l:
      let
        m = builtins.match ".*inherit \\(cata\\) ([^;]*);.*" l;
      in
      if m == null then [ ] else lib.filter (w: w != "") (lib.splitString " " (lib.head m))
    ) (lib.splitString "\n" flakeSrc)
  );

  missing = lib.filter (n: !(exposed ? ${n})) wanted;
in
lib.throwIf (missing != [ ])
  (
    "templates/consumer/flake.nix reads ${lib.concatMapStringsSep ", " (n: "`cata.${n}`") missing}, "
    + "which `legacyPackages` does not expose. A consumer following the template gets "
    + "\"attribute missing\" on their first build."
  )
  {
    consumer-template = pkgs.runCommand "consumer-template" { } ''
      ln -s ${named.package} rendered
      echo "${lab.name}: ${toString (lib.length (lib.attrNames lab.clusters))} cluster, cliConfig ${named.cliConfig.labName}" > $out
    '';
  }
