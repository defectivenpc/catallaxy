# netbird's operator: mesh state as CRs, reconciled against a control plane
# that need not be in this cluster.
#
# ## Why this is not part of `floes/cluster/netbird`
#
# It was, and the split is the point. A mesh has one control plane and as many
# clusters on it as the mesh has members, so the two halves have different
# multiplicities — one netbird, N operators — and a floe cannot be
# instantiated twice in one link. Putting them together made "which cluster
# runs the control plane" and "which clusters are on the mesh" the same
# question, which is exactly what a mesh exists to make different.
#
# ## The three scopes this floe sits across
#
# **The chart.** `chart` is a store path and its values are this floe's own
# business. Nothing outside reads or writes them: what a lab configures is a
# hostname and a namespace, and what a peer floe sees is a signature. A chart
# whose values leaked into the lab's option tree would make every consumer
# depend on the chart's schema, which changes when the chart does.
#
# **The cluster.** `MESH_OPERATOR` is what this promises, and every field of
# it is `T.local`: a controller running here, CRDs installed here, a router in
# a namespace here. A floe that wants its Service on the mesh requires it and
# gets ordered after the CRDs by the derived `kind:` edge. That promise is
# refused as a lab-scope offer, which is correct — an operator in `core` does
# not reconcile a CR applied in `obs`.
#
# **The lab.** `MESH_NETWORK` is what this requires, and it is the one that
# travels. In the cluster running the control plane it resolves locally; in
# any other it resolves from the lab scope, where `managementUrl` reads and
# `managementInternalUrl` is a throw naming the field. This floe uses the
# routed name in *both* cases — see `managementUrl` below.
{
  floe,
  cataCharts ? null,
  lib,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "netbird-operator";
  summary = "The NetBird operator, which joins this cluster to a mesh another one runs.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.netbird-operator.chart}";
      defaultText = lib.literalExpression "cataCharts.netbird-operator.chart";
      description = ''
        Store path of the netbird-operator chart. Required.

        The operator is what makes mesh state declarative: groups, setup keys,
        routers and the Services exposed on the mesh are all CRs it
        reconciles. Without it a lab is back to clicking a setup key into the
        dashboard and hoping nothing drifts.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "netbird";
      description = ''
        Namespace the operator runs in.

        Its own, not the control plane's. In the cluster that also runs
        netbird the two coincide and nothing notices; in any other there is no
        control plane here to share a namespace with, and defaulting to
        whatever `MESH_NETWORK.namespace` said would be reading a field the
        shared signature does not carry, for exactly this reason.
      '';
    };

    tokenSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "netbird/netbird-api-token";
      description = ''
        Where this cluster's copy of the personal access token lives, as
        `<namespace>/<name>`, or null to resolve it through `MESH_ADMIN`.

        Null is right in the cluster that runs the control plane: netbird
        mints the token there and promises where it put it, so saying it again
        here is a second place to be wrong. In any other cluster nothing
        provides `MESH_ADMIN` — a reference to a Secret does not cross a
        cluster boundary and `link` refuses to let it try — so the *value*
        arrives through `lab.clusters.<c>.secrets.subscribe` and this says
        where that lands it.

        That is the seam, stated plainly: a secret's address is allocated by
        the lab, and the lab is what knows both sides of a subscription.
      '';
    };

    tokenKey = lib.mkOption {
      type = lib.types.str;
      default = "token";
      description = "Key within `tokenSecret` holding the token. Ignored when it is null.";
    };
  };

  # The mesh to reconcile against. The one hole here that crosses a cluster
  # boundary, and the reason this floe exists apart from the control plane.
  #
  # The *shared* signature, which is the narrower one: `managementUrl` and
  # `dashboardUrl`, and not `namespace` or `managementInternalUrl`. Declaring
  # what this reads is what makes the floe placeable either beside the control
  # plane or a cluster away — the name is the same, so it resolves against
  # whichever provider is there, and the check decides whether the fields it
  # asked for are available where it was put. Asking for the full signature
  # would pin it to the control plane's own cluster.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.mesh = sigs.MESH_NETWORK_SHARED;

  # Where the token is, when something in this cluster knows. Optional because
  # in every cluster but one, nothing here can know — and `optional` is
  # how a floe says "resolve this if the link can" without a lab having to
  # tell it whether the link can.
  optional.meshAdmin = sigs.MESH_ADMIN;

  provides.meshOperator = sigs.MESH_OPERATOR;

  out.component = kinds.component;
  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        mesh = config.floe.requires.mesh;
        admin = config.floe.requires.meshAdmin or null;

        ns = inputs.namespace;

        parsed =
          if inputs.tokenSecret == null then
            null
          else
            let
              parts = lib.splitString "/" inputs.tokenSecret;
            in
            {
              namespace = lib.elemAt parts 0;
              name = lib.elemAt parts 1;
              key = inputs.tokenKey;
              wellFormed = lib.length parts == 2;
            };

        token =
          if admin != null then
            admin.tokenSecret
          else if parsed != null then
            removeAttrs parsed [ "wellFormed" ]
          else
            null;

        crdKinds = [
          "netbird.io/Group"
          "netbird.io/NBGroup"
          "netbird.io/NBPolicy"
          "netbird.io/NBResource"
          "netbird.io/NBRoutingPeer"
          "netbird.io/NBSetupKey"
          "netbird.io/NetworkResource"
          "netbird.io/NetworkRouter"
          "netbird.io/SetupKey"
        ];
      in
      {
        config.floe.provides.meshOperator = {
          namespace = ns;
          inherit crdKinds;

          routerRef = null;
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          bundles.operator = kinds.mkBundle {
            createNamespaces = [ ns ];

            helmCharts.netbird-operator = kinds.mkHelmChart {
              inherit (inputs) chart;
              releaseName = "netbird-operator";
              namespace = ns;
              values = {
                managementURL = mesh.managementUrl;

                netbirdAPI.keyFromSecret = {
                  inherit (token) name key;
                };

                webhook.failurePolicy = "Ignore";
              };
            };

            needsSecrets = [ "${token.namespace}/${token.name}" ];

            images.operator = kinds.mkImage "ghcr.io/netbirdio/netbird-operator:v0.7.0";

            crds = crdKinds;

            ready = kinds.readyDeployment {
              name = "netbird-operator";
              namespace = ns;
            };
          };

          assertions = [
            {
              assertion = token != null;
              message =
                "nothing in this cluster provides MESH_ADMIN and `tokenSecret` is null, "
                + "so there is no personal access token for the operator to spend. In the "
                + "cluster running netbird, leave it null and the control plane answers; "
                + "in any other, subscribe to the token and name where it lands.";
            }
            {
              assertion = admin == null || inputs.tokenSecret == null;
              message =
                "`tokenSecret` is '${toString inputs.tokenSecret}' and this cluster also "
                + "provides MESH_ADMIN. Two answers to where one token is, and they can "
                + "disagree — drop the input and let the control plane say.";
            }
            {
              assertion = parsed == null || parsed.wellFormed;
              message = "tokenSecret is '${toString inputs.tokenSecret}'; it names a Secret as '<namespace>/<name>'";
            }
            {
              assertion = token == null || token.namespace == ns;
              message =
                "the token is in namespace '${toString (token.namespace or "?")}' and the operator "
                + "runs in '${ns}'; the chart reads it through a secretKeyRef, which only "
                + "resolves within the pod's own namespace";
            }
          ];

          backs.meshOperator = [ "operator" ];
        };
      }
    )
  ];
}
