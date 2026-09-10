# netbird-operator, alone.
#
# The first floe written to run in a cluster other than the one its dependency
# is in, so what is worth pinning is the seam: which URL it dials, where it
# expects the token, and that it refuses rather than guesses when nobody has
# said.
#
# The isolation harness gives it a local `MESH_ADMIN` stub, which is the
# control-plane cluster's arrangement. The cross-cluster one — `MESH_ADMIN`
# absent, `tokenSecret` set — is the `without` case below.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  evalWith =
    args:
    support.evalFloe (
      {
        name = "netbird-operator";
        inputs = {
          chart = "/dev/null";
        }
        // (args.inputs or { });
      }
      // removeAttrs args [ "inputs" ]
    );

  r = evalWith { };
  values = r.bundles.operator.helmCharts.netbird-operator.values;

  # The other cluster: no control plane here, so nothing provides MESH_ADMIN
  # and the lab says where the subscription landed the token.
  remote = evalWith {
    without = [ "meshAdmin" ];
    inputs.tokenSecret = "netbird/nb-token";
  };
in
lib.runTests {

  # ---- which URL ---------------------------------------------------------

  # The routed name, in every cluster including the control plane's own.
  #
  # `managementInternalUrl` is a Service address and would be one hop shorter
  # at home. The floe cannot ask for it: it is `T.local`, so it reads in one
  # instantiation and throws in another, and nothing tells a floe body which
  # link it is in — deliberately. One code path that works from either side.
  testItDialsTheRoutedName = {
    expr = values.managementURL;
    expected = support.stubs.mesh.value.managementUrl;
  };

  # The paired negative, and the whole reason the test above is not a
  # tautology: reading the internal URL through a scope entry is a throw, so a
  # floe that reached for it would work in one cluster and fail in the next.
  testTheInternalUrlIsNotWhatItUses = {
    expr = values.managementURL == support.stubs.mesh.value.managementInternalUrl;
    expected = false;
  };

  # ---- where the token is ------------------------------------------------

  # Beside the control plane: netbird chose the Secret's name and netbird said
  # so, so the lab says nothing and the two cannot disagree.
  testItTakesTheTokenAddressFromTheControlPlane = {
    expr = values.netbirdAPI.keyFromSecret;
    expected = {
      inherit (support.stubs.meshAdmin.value.tokenSecret) name key;
    };
  };

  # In another cluster there is nothing to ask, so the lab says — which is the
  # same thing it already said on the subscription's other end.
  testInAnotherClusterTheLabSaysWhereTheTokenLanded = {
    expr = remote.bundles.operator.helmCharts.netbird-operator.values.netbirdAPI.keyFromSecret;
    expected = {
      name = "nb-token";
      key = "token";
    };
  };

  # Nothing in the manifest stream creates it — netbird's Job did, in another
  # cluster, or a subscription will. The cluster still has to know it is
  # required, or the operator is a pod that never starts and a lab with no
  # idea why.
  testItTellsTheClusterItNeedsTheToken = {
    expr = r.bundles.operator.needsSecrets;
    expected = [ "netbird/netbird-api-token" ];
  };

  # ---- the refusals ------------------------------------------------------

  # Neither source. This is the cross-cluster mistake — instantiating the
  # operator in a second cluster and forgetting the subscription — and it has
  # no runtime symptom beyond a CrashLoopBackOff in a chart nobody wrote.
  testWithNeitherSourceItRefuses = {
    expr = map (a: a.assertion) (evalWith { without = [ "meshAdmin" ]; }).component.assertions;
    expected = [
      false
      true
      true
      true
    ];
  };

  # Both sources. Two answers to where one token is, and they can disagree —
  # so the input is refused rather than silently winning or silently losing.
  testWithBothSourcesItRefuses = {
    expr =
      map (a: a.assertion)
        (evalWith {
          inputs.tokenSecret = "netbird/somewhere-else";
        }).component.assertions;
    expected = [
      true
      false
      true
      true
    ];
  };

  # The chart reads the token through a `secretKeyRef`, which only resolves in
  # the pod's own namespace. A subscription landing it elsewhere produces a
  # Deployment that never starts, and the error names a Secret rather than the
  # subscription that put it in the wrong place.
  testATokenInAnotherNamespaceIsRefused = {
    expr =
      map (a: a.assertion)
        (evalWith {
          without = [ "meshAdmin" ];
          inputs.tokenSecret = "elsewhere/nb-token";
        }).component.assertions;
    expected = [
      true
      true
      true
      false
    ];
  };

  # ---- what it promises --------------------------------------------------

  # Every field local, which is what keeps it out of a lab scope: an operator
  # in one cluster does not reconcile a CR applied in another, and the CRDs it
  # names are installed here and nowhere else.
  testWhatItPromisesCannotTravel = {
    expr = support.catallaxy.floe.isUncrossable support.catallaxy.sigs.MESH_OPERATOR;
    expected = true;
  };

  # Declared but not routed. A NetworkResource attaches to a router, and this
  # floe installs no routing peer — so a consumer can see that rather than
  # render a reference the operator rejects.
  testItPromisesNoRouterUntilOneRuns = {
    expr = r.provides.meshOperator.routerRef;
    expected = null;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

}
