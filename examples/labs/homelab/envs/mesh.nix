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
    The gateway cannot complete the TLS hop to kanidm, so every OIDC flow in
    this lab — including netbird's token exchange — gets a 500.

    kanidm has no plaintext mode, so the hop from the gateway to it is HTTPS
    and the gateway has to validate what signed it. Traefik validates against
    the *pod IP* rather than the hostname
    (`x509: cannot validate certificate for 10.244.0.x because it doesn't
    contain any IP SANs`), and the `BackendTLSPolicy` that would tell it the
    hostname does not exist: kaniop renders one from `Kanidm.spec.gateway`,
    but `BackendTLSPolicy` is `gateway.networking.k8s.io/v1alpha3` and lives
    in Gateway API's *experimental* channel, while `gateway-api-crds` installs
    the standard one.

    So the next step is the CRD channel, not netbird. Everything up to it
    works: the service account reconciles, kaniop mints and rotates its token,
    the token step reads it and reaches the exchange endpoint.
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
