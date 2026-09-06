# homelab, with a mesh control plane on `core` and both clusters on the mesh.
#
# This is the lab that exercises all three scopes at once, which is what makes
# it worth having beside `homelab.local`:
#
# **Chart.** `netbird-operator` wraps a helm chart, and nothing outside that
# floe names a chart value. Both clusters instantiate the same floe with the
# same chart and differ in exactly one input.
#
# **Cluster.** Each cluster's operator promises `MESH_OPERATOR`, every field of
# which is link-local — a controller here, CRDs here. Neither cluster can offer
# it to the other and neither should: an operator in `core` does not reconcile
# a CR applied in `obs`.
#
# **Lab.** `core` offers one promise, `netbird/mesh`. `obs` runs no control
# plane, so its operator's `MESH_NETWORK` hole finds nothing local and resolves
# from the lab scope — where `managementUrl` reads and `managementInternalUrl`
# is a throw naming the field.
#
# netbird lives on `core` beside kanidm because it has to: it has no local
# accounts at all, so a netbird without an issuer in the same cluster is one
# nobody — including its own operator — can log into.
#
# What this proves that `every-floe` cannot: four workloads that fail apart
# rather than together actually come up. Management renders its config from a
# template with two credentials substituted by an init container, and if that
# substitution does not happen the server starts anyway and refuses every peer.
# `cata --flake .#homelab.mesh lab ops -- mesh core-netbird-config` asks the
# running server whether any placeholder survived.
#
# ## The token, and why it is not a signature
#
# The operator spends a netbird personal access token. `core` mints it and
# promises where it landed (`MESH_ADMIN`), which `core`'s own operator resolves
# with nothing said here. `obs` cannot resolve that promise — a reference to a
# Secret in another cluster's namespace means nothing, and `link` refuses to
# let it try — so the *value* crosses the way every value does, through
# `lab.secrets.{publish,subscribe}`, and `obs`'s operator is told where the
# subscription put it.
#
# Two mechanisms, and the split is not an accident: a signature carries
# configuration and a subscription carries content. Threading the token through
# a signature would put secret material in a rendered manifest, which is the
# one thing no floe may do.
{
  cataCharts,
  floes,
  config,
  ...
}:

let
  zone = config.lab.dns.zone;

  # Where the runtime store answers, as seen from either cluster. Routed,
  # because `obs` reads a value `core` wrote and an in-cluster Service address
  # resolves in one of them — which is exactly what `VAULT_SERVER.address`
  # being the in-cluster one, and this being a lab decision, means.
  vaultServer = "https://vault.${zone}";

  # Everything a cluster needs to take part in the runtime store. `core` also
  # runs the store; `obs` only reads and writes through it.
  storeClient = {
    secret-store = floes.secret-store {
      labStore = "runtime";
      server = vaultServer;
    };
  };

  tokenProjection.vault-token = {
    source = "vault-credential";
    namespace = "external-secrets";
    keys.token.from = "token";
  };

  # The token, in the one place its address is written. `core`'s netbird mints
  # it under this name and `obs`'s subscription lands it under the same one, so
  # the two operators are instantiated identically apart from which of them has
  # a control plane to ask.
  patSecret = "netbird-api-token";
  patNamespace = "netbird";
in
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
    after that is declarative — both operators reconcile groups, setup keys,
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

  # Two stores, because a value one cluster mints has to be writable. The
  # authored one holds the runtime one's credential and nothing else.
  lab.secrets.stores = {
    authored.backend = "sops";
    runtime = {
      backend = "vault";
      vault.server = vaultServer;
    };
  };

  lab.secrets.managed.vault-credential = {
    store = "authored";
    keys.token.generator = "hex";
    keys.token.length = 32;
  };

  lab.clusters.core = {
    floes = storeClient // {
      # The store, and the one cluster that runs it.
      openbao = floes.openbao { chart = "${cataCharts.openbao.chart}"; };

      netbird = floes.netbird { };

      # Beside the control plane, so `tokenSecret` is null: netbird promises
      # `MESH_ADMIN` and the operator resolves it. Naming the Secret here would
      # be a second place for it to be wrong, and the floe refuses both answers
      # at once rather than picking one.
      netbird-operator = floes.netbird-operator {
        chart = "${cataCharts.netbird-operator.chart}";
      };
    };

    # One promise, not the unit. `netbird` also provides `MESH_ADMIN`, which is
    # a reference to a Secret in this cluster and can never mean anything
    # anywhere else — offering the unit would offer both, and the lab refuses
    # that where the line is written.
    provides = [ "netbird/mesh" ];

    secrets.project = tokenProjection;
    secrets.publish.${patSecret}.namespace = patNamespace;
  };

  lab.clusters.obs = {
    floes = storeClient // {
      # No netbird here. Its `MESH_NETWORK` hole finds nothing in this cluster
      # and resolves from the lab scope, which is the point of the lab.
      netbird-operator = floes.netbird-operator {
        chart = "${cataCharts.netbird-operator.chart}";

        # Nothing here provides `MESH_ADMIN`, so the lab says where the
        # subscription below landed the token. That is the seam between the two
        # mechanisms, and it is one line.
        tokenSecret = "${patNamespace}/${patSecret}";
      };
    };

    secrets.project = tokenProjection;

    secrets.subscribe.${patSecret} = {
      from = "core";

      # The operator's own namespace. The chart reads the token through a
      # `secretKeyRef`, which resolves only within the pod's namespace, and the
      # floe refuses a subscription that lands it anywhere else.
      namespace = patNamespace;
      secret = patSecret;
    };
  };
}
