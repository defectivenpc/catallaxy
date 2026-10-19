# Whether a lab is refused, for a case whose whole subject is the refusal.
#
#   refuses (bentLab { … })   => true when the assembly is rejected
#
# A negative case cannot live inside the thing it is about: if the lab is
# refused it does not evaluate, so neither would a check placed in it. That is
# why these stay in `nix/checks/` rather than becoming policies — they are
# about an assembly that must not exist.
#
# `tryEval` catches the assertion `lib/lab.nix` throws and the link error the
# floe library throws. `deepSeq` because the failure is inside a lazily held
# field: forcing the document shallowly returns an attrset and proves nothing.
#
# It cannot catch a missing attribute or an `abort`, which is why the linker
# throws rather than asserting.
{ lib }:

lab: !(builtins.tryEval (builtins.deepSeq lab.cliConfig "evaluated")).success
