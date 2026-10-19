# A list of findings, as a derivation that fails when the list is not empty.
#
#   refuse "lab-host-ports" "Two containers cannot bind one host port." clashes
#
# Every finding is printed, then `what` — the sentence saying why it matters,
# once, after the evidence. A check that reports nothing still builds, so the
# check's own name appears in the green bar rather than being absent from it.
{ lib, pkgs }:

checkName: what: findings:
pkgs.runCommand checkName { } ''
  ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
  ${lib.optionalString (findings != [ ]) ''
    echo "" >&2
    echo ${lib.escapeShellArg what} >&2
    exit 1
  ''}
  touch $out
''
