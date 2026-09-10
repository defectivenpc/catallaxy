# nop-resource, alone.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };
  r = support.evalFloe { name = "nop-resource"; };
  nop = r.bundles.nop.resources.nop;
in
lib.runTests {

  testRendersSomething = {
    expr = r.bundles != { };
    expected = true;
  };

  testClaimsItsImages = {
    expr = r.component.imagesComplete;
    expected = true;
  };

  # Cluster-scoped, read off the package rather than recalled: v0.4.0 ships
  # one CRD at `scope: Cluster`. Giving it a namespace is accepted by the
  # renderer and refused by the API server.
  testItIsClusterScoped = {
    expr = {
      inherit (nop) apiVersion kind;
      hasNamespace = nop.metadata ? namespace;
      probeIsClusterScoped = !(r.bundles.nop.ready ? namespace);
    };
    expected = {
      apiVersion = "nop.crossplane.io/v1alpha1";
      kind = "NopResource";
      hasNamespace = false;
      probeIsClusterScoped = true;
    };
  };

  # The whole point: it reports Ready without creating anything, so a lab can
  # run the reconcile path with no account behind it.
  testItGoesReadyOnATimer = {
    expr = nop.spec.forProvider.conditionAfter;
    expected = [
      {
        time = "10s";
        conditionType = "Ready";
        conditionStatus = "True";
      }
    ];
  };

  # The probe has to outlast the condition it waits for, and the provider
  # polls every 10s, so the two must not be close.
  testTheProbeOutlastsTheCondition = {
    expr = r.bundles.nop.ready.timeout;
    expected = "3m";
  };

  # Short kind: `cata lab lint` matches a probe against the rendered object's
  # normalised kind, and a qualified one never matches.
  testTheProbeNamesTheRenderedObject = {
    expr = r.bundles.nop.ready.resource;
    expected = "nopresource/nop";
  };
}
