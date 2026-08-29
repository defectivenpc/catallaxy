{ lib, pkgs }:

# Turning a list of failure strings into a check derivation.
#
# Seven checks wrote this out, each with the same shape: succeed with a
# message, or print a prose explanation followed by the failures and exit 1.
#
# One did not — `host-dns` used `throw`, which is worse than it looks. A throw
# during evaluation is not a failing check; it is a failing *evaluation*, so
# `nix flake check` cannot get as far as building the other two hundred
# derivations and reports nothing about them. A check that fails should fail
# alone.

{
  # `what` is the derivation name, `why` the prose an operator reads above the
  # list, and `failures` the list — empty meaning pass.
  mkCheck =
    {
      what,
      why,
      failures,
      passed ? "ok",
      # What to do about it, printed after the list. For a check whose remedy
      # is a command rather than a code change.
      fix ? "",
    }:
    pkgs.runCommand what { } (
      if failures == [ ] then
        ''
          echo ${lib.escapeShellArg passed} > $out
        ''
      else
        ''
          cat >&2 <<'EOF'
          ${why}

          ${lib.concatStringsSep "\n" (map (f: "  - ${f}") failures)}
          ${lib.optionalString (fix != "") "\n${fix}"}
          EOF
          exit 1
        ''
    );
}
