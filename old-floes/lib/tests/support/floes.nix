# Floes for platform tests that need a concrete one.
#
# Most of `lib/tests` exercises the platform against fixtures it builds
# itself. A few cannot: a test about what `lab.secrets` renders needs a floe
# that actually asks for a secret, and inventing a fake one would test the
# fake. Those name the real floes they borrow, and get exactly those rather
# than the whole set — so the test says which parts of the distro it leans on,
# and a test that starts leaning on more has to say so.
#
# In a subdirectory because `nix/checks/lib-tests.nix` asserts that every
# `.nix` directly under `lib/tests` is registered as a suite, and this is a
# helper rather than a suite.
{ lib }:

let
  all = import ../../../floes/cluster/set.nix;

  missing = names: lib.subtractLists (lib.attrNames all) names;
in

names:
assert lib.assertMsg (missing names == [ ]) ''
  lib/tests asked for floes the shipped set does not have: ${lib.concatStringsSep ", " (missing names)}.

  Either the floe was renamed in floes/cluster/set.nix, or the test wants one
  that does not exist. A silently empty module list here would make the test
  pass by rendering nothing.
'';
map (n: all.${n}) names
