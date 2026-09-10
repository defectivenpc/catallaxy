# The generated option reference.
#
# `cata-build docs render` and `nix/option-docs.nix` are the two halves: the
# JSON comes from `nixosOptionsDoc` over the tree `mkLab` evaluates, and the
# splicer routes it into pages and a nav block.
{
  lib,
  pkgs,
  cata,
  optionsJSON,
  summary ? ../docs/book/src/SUMMARY.md,
}:

pkgs.runCommand "option-docs" { } ''
  mkdir -p $out
  ${cata}/bin/cata-build docs render \
    ${optionsJSON}/share/doc/nixos/options.json \
    ${summary} \
    $out
''
