# lab-services, alone.
#
# A collector with nothing to decide: it hands back what it collected, keyed by
# who provided it. So the one thing worth pinning is that key, because it is a
# CLI contract — `cli/src/host/state.rs` keys a service's state directory by
# it, and two call sites look up `registry`, `dns` and `proxy` by literal
# string.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  servicesWith =
    without:
    (support.evalFloe {
      name = "lab-services";
      inherit without;
    }).link.out."catallaxy.labServices".lab-services;
in
lib.runTests {

  # Keyed by the contributing floe's unit name, which is the name `cata` knows
  # the service as. Nothing renames and nothing re-keys: the collection
  # carries the name, which is the whole reason this is a signature and not an
  # output kind — an output kind would have left the fold to whoever holds the
  # link, which is where it used to be.
  testItKeysEachServiceByTheFloeThatRunsIt = {
    expr = lib.attrNames (servicesWith [ ]);
    expected = [ "stub-service" ];
  };

  # Verbatim. A collector that reshaped a contribution would be a second place
  # the record's fields are decided, and `HOST_SERVICE` is already where they
  # are checked.
  testItHandsTheRecordBackUnchanged = {
    expr = (servicesWith [ ]).stub-service;
    expected = support.stubs.service.value;
  };

  # A lab that runs no containers collects nothing, and the empty set is what
  # `setup-services` is gated on — so this is the case that decides whether the
  # step exists at all, not a degenerate one.
  testALabThatRunsNothingSaysSo = {
    expr = servicesWith [ "service" ];
    expected = { };
  };
}
