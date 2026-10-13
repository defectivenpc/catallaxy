# The containers the lab runs on the operator's machine, folded into one
# statement.
#
# A collector: it answers no signature and installs nothing, and its whole job
# is the fan-in. Every host floe in the lab provides a `HOST_SERVICE` and this
# hands them back keyed by the floe that provided it — which is the name
# `cata` knows the service as, because a collection is keyed by contributor.
#
# It was `modules/lab/host/default.nix`, which read `catallaxy.hostService` off
# the link. That had to be the container's job: an output kind is folded by
# whoever holds the link, so the fold could not be a unit of the thing it was
# folding. A signature can, and this is it.
{
  lib,
  floe,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "lab-services";
  summary = "Folds every host floe's container into the one set `setup-services` starts.";

  # One set, so one of these. Two would describe overlapping halves of the
  # same namespace, and that namespace is a CLI contract.
  singleton = true;

  collects.service = sigs.HOST_SERVICE;

  out.labServices = kinds.labServices;

  body =
    { collects, ... }:
    {
      out.labServices = collects.service;
    };
}
