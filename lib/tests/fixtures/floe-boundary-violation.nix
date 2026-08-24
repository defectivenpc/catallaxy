{ config, lib, ... }:

# Not a floe. A fixture the boundary check reads as text, to prove its
# extractor still finds what it is looking for.
#
# The check pulls `config.floes.<x>.<y>` out of floe sources with a regex,
# because Nix has no parser to ask. A regex that stops matching does not
# fail — it returns nothing, and no violations reads exactly like a clean
# tree. So the check runs itself against this file too and fails if it
# cannot find the one violation planted here.
#
# It carries all three shapes, so a change that over-matches fails as well
# as one that under-matches.

let
  # A VIOLATION: another floe's internal state, not its interface. This is
  # the line the check must find.
  gatewayNamespace = config.floes.gateway.namespace;

  # Fine: another floe's published interface.
  gatewayName = config.floes.gateway.exports.gatewayName;

  # Fine: this pretend floe's own config.
  enabled = config.floes.canary.enable;
in
{
  inherit gatewayNamespace gatewayName enabled;
  unused = lib.id;
}
