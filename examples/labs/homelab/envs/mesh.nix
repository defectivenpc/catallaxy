# homelab, with a mesh control plane on `core`.
#
# netbird beside kanidm, which is where it has to be: its OIDC hole resolves
# within a cluster and it has no local accounts at all, so a netbird without an
# issuer in the same cluster is one nobody — including its own operator — can
# log into.
#
# What this proves that `every-floe` cannot: four workloads that fail apart
# rather than together actually come up. Management renders its config from a
# template with two credentials substituted by an init container, and if that
# substitution does not happen the server starts anyway and refuses every
# peer. `cata --flake .#homelab.mesh lab ops -- mesh core-netbird-config` asks
# the running server whether any placeholder survived.
#
# The mesh has no members yet. Joining one needs a setup key, setup keys are
# reconciled by netbird's operator, and the operator authenticates with a
# token minted against a kanidm service account this platform does not create
# — see the header of `floes/cluster/netbird`. So this stands the control
# plane up and stops there, which is a real thing to have: the dashboard is
# reachable, an operator logs in with their kanidm identity, and a peer can be
# registered by hand.
{ cataCharts, floes, ... }:
{
  lab.name = "homelab.mesh";

  lab.unstable = ''
    netbird's operator needs a personal access token, minting one needs an
    identity netbird will accept, and kanidm 1.6.4 cannot issue this platform
    one without a human.

    The token step exchanges the service account's kanidm API token for an
    OIDC token with netbird's audience. kanidm's token endpoint supports
    `authorization_code`, `client_credentials`, `refresh_token` and
    `device_code` — and not `token-exchange`, which is what the parked floe
    used and what this one inherited. `client_credentials` is the only
    non-interactive one left, and it needs a *confidential* client, while
    netbird's must be public so the dashboard can use PKCE. One audience,
    two incompatible requirements.

    So the first identity has to arrive through a browser: a human logs in,
    becomes the account owner, and a PAT is minted from there. Everything
    after that is declarative — the operator reconciles groups, setup keys,
    routers and network resources from CRs, and the heal CronJob keeps the
    token true.

    Verified working up to this point, on a live cluster: kanidm answers
    through the gateway, the service account reconciles, kaniop mints and
    rotates its API token, and the token step reads it and reaches the
    exchange endpoint.
  '';
  # Its own everything, so it renders and runs beside the other two.
  lab.network.subnet = "172.36.0.0/16";
  lab.proxy.httpPort = 8086;
  lab.proxy.httpsPort = 8449;
  lab.dns.hostPort = 5362;
  lab.registry.port = 5058;
  lab.egress.port = 3135;

  # One line. `reloader` is already on `core` from the base lab and declaring
  # it again is a conflicting definition rather than a merge — a floe instance
  # is an opaque value and the module system has no merge for two of them.
  lab.clusters.core.floes.netbird = floes.netbird {
    operatorChart = "${cataCharts.netbird-operator.chart}";
  };
}
