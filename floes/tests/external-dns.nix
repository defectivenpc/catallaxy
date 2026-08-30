# external-dns, alone.
#
# The first floe that contributes a plan step, so this is also where the
# contract for one is pinned: what it declares, and that it declares it only
# when there is something to clean up.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  evalWith =
    extra:
    support.evalFloe {
      name = "external-dns";
      inputs = {
        chart = "/dev/null";
        zone = "lab.test";
        dnsServer = "172.20.0.1";
        tsigSecretRef = "external-dns/externaldns-tsig";
      }
      // extra;
    };

  r = evalWith { };
  values = r.bundles.external-dns.helmCharts.external-dns.values;
  step = r.component.steps.purge-records;

  # `deepSeq` so a lazy throw inside the value is forced rather than passed
  # over as a value that happens not to be looked at.
  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
in
lib.runTests {

  # ---- the secret ------------------------------------------------------

  # The whole reason the floe takes a reference instead of the value. The
  # parked floe passed `--rfc2136-tsig-secret=<key>`, which renders the key
  # into the Deployment's argv, where `get pod` shows it and where the
  # rendered manifest carries it into the store.
  testTheTsigKeyIsNeverAnArgument = {
    expr = lib.any (a: lib.hasPrefix "--rfc2136-tsig-secret=" a) values.extraArgs;
    expected = false;
  };

  testTheTsigKeyArrivesFromASecret = {
    expr = (lib.head values.env).valueFrom.secretKeyRef;
    expected = {
      name = "externaldns-tsig";
      key = "tsig-secret";
    };
  };

  # A `secretKeyRef` only resolves within the pod's own namespace, so a
  # reference into another one is a Deployment that never starts.
  testItRefusesASecretInAnotherNamespace = {
    expr = map (a: a.assertion) (
      (evalWith { tsigSecretRef = "elsewhere/externaldns-tsig"; }).component.assertions
    );
    expected = [
      false
      true
    ];
  };

  # The lab has to know something must land this Secret; nothing in the
  # rendered manifests names it, because the value never appears there.
  testItTellsTheClusterWhatItNeeds = {
    expr = r.bundles.external-dns.needsSecrets;
    expected = [ "external-dns/externaldns-tsig" ];
  };

  # ---- the zone --------------------------------------------------------

  # Without a filter external-dns treats every record in the server as its
  # own, and `sync` then deletes the ones it did not create.
  testTheZoneIsAlsoTheDomainFilter = {
    expr = values.domainFilters;
    expected = [ "lab.test" ];
  };

  testItRefusesATrailingDot = {
    expr = map (a: a.assertion) ((evalWith { zone = "lab.test."; }).component.assertions);
    expected = [
      true
      false
    ];
  };

  # Two clusters publishing into one zone each need to know which records are
  # theirs, and the chart's default — the release name — is the same in both.
  testTheOwnerIdIsTheCluster = {
    expr = values.txtOwnerId;
    expected = support.stubs.cluster.value.name;
  };

  # ---- the step --------------------------------------------------------

  testItContributesATeardownStep = {
    expr = {
      inherit (step) kind direction;
      onFailure = step.policy.onFailure;
      before = step.before;
    };
    expected = {
      kind = "run-script";
      direction = "teardown";

      # A zone left dirty is bad; a lab that cannot be destroyed is worse.
      # Everything after this step is what frees the ports and the network.
      onFailure = "continue";

      before = [ "optional:provides:cluster/${support.stubs.cluster.value.name}/destroyed" ];
    };
  };

  # Only `sync` deletes, so only `sync` can leave anything behind. A teardown
  # step with nothing to do still costs the drain wait.
  testOnlyASyncingControllerNeedsCleaningUpAfter = {
    expr = lib.attrNames (evalWith { policy = "upsert-only"; }).component.steps;
    expected = [ ];
  };

  # ---- the rest --------------------------------------------------------

  # A source whose kind does not exist is not a warning: external-dns fails
  # its own startup check and crash-loops. Two of the four defaults are
  # Gateway API kinds, which is why the floe requires them.
  testItWatchesGatewayRoutes = {
    expr = lib.intersectLists values.sources [
      "gateway-httproute"
      "gateway-tlsroute"
    ];
    expected = [
      "gateway-httproute"
      "gateway-tlsroute"
    ];
  };

  # A k3d Service reports a cluster-internal LoadBalancer address, so a lab
  # behind one ingress has to override what every record points at.
  testDefaultTargetsBecomeAnArgument = {
    expr = (
      lib.filter (a: lib.hasPrefix "--default-targets=" a)
        (evalWith { defaultTargets = [ "172.20.0.1" ]; })
        .bundles.external-dns.helmCharts.external-dns.values.extraArgs
    );
    expected = [ "--default-targets=172.20.0.1" ];
  };

  testAnUnparseableIntervalIsRefused = {
    expr = throws (evalWith { interval = "every so often"; }).component;
    expected = true;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  testDeclaresItsNetwork = {
    expr = r.component.network.declared;
    expected = true;
  };
}
