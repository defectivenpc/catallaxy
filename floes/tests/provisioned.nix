# provisioned, alone.
#
# The floe that proves the `resources` category is a category and not a
# special case: same `mkFloe`, same `requires.cluster`, a different output
# kind. `lib/tests/render-infra.nix` covers what the renderer does with these;
# this covers what the floe declares.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  plain = support.evalFloe {
    name = "provisioned";
    inputs.stateDir = "/tmp/fixture";
  };

  published = support.evalFloe {
    name = "provisioned";
    inputs = {
      stateDir = "/tmp/fixture";
      publishTo = {
        store = "runtime";
        key = "app/identity";
      };
    };
  };

  resources = r: r.link.out."catallaxy.resources".provisioned;
  publications = r: r.link.out."catallaxy.publications".provisioned or { };
in
lib.runTests {

  # Before any cluster exists is the case the reconcile camp cannot cover at
  # all: no reconciler, no CRD, and nowhere to put a credential. That is the
  # whole reason RFC 0003 §1 says the second camp cannot be dissolved into
  # the first.
  testItProvisionsBeforeAnyClusterExists = {
    expr = lib.mapAttrs (_: r: r.phase) (resources plain);
    expected = {
      identity = "before-clusters";
      marker = "before-clusters";
    };
  };

  # Declared, never inferred (RFC 0003 §3). A typo in a consumer's reference
  # then fails at evaluation naming the resource and the output, rather than
  # part-way through an apply that has already created things.
  testOutputsAreDeclared = {
    expr = lib.mapAttrs (_: r: r.outputs) (resources plain);
    expected = {
      identity = [ "result" ];
      marker = [ "id" ];
    };
  };

  # A reference is a deferred token, not a string with a sentinel in it. That
  # is what lets `checkValue` refuse one where a manifest field is expected —
  # reported where it was written rather than found by scanning rendered
  # output afterwards.
  testAReferenceIsADeferredValueAndNotAString = {
    expr =
      let
        c = (resources plain).marker.inputs.content;
      in
      {
        deferred = c.__deferred or false;
        path = c.path or null;
      };
    expected = {
      deferred = true;
      path = [
        "identity"
        "result"
      ];
    };
  };

  # Nothing here names Terraform, OpenTofu or Pulumi — RFC 0003 §12.10. The
  # vocabulary is the registry's, which is a borrowed namespace rather than a
  # borrowed implementation.
  testItNamesNoTool = {
    expr = lib.mapAttrs (_: r: "${r.provider}.${r.type}") (resources plain);
    expected = {
      identity = "random.random_password";
      marker = "local.local_file";
    };
  };

  # The join between the two camps. Off by default, because a resource whose
  # value stays in state is a complete arrangement — publishing is what a lab
  # asks for when a cluster has to read the value back.
  testNothingIsPublishedUntilTheLabAsks = {
    expr = publications plain;
    expected = { };
  };

  testAPublicationNamesAStoreTheLabAlreadyHas = {
    expr = (publications published).credential;
    expected = {
      resource = "identity";
      output = "result";
      store = "runtime";
      key = "app/identity";
    };
  };

  # It is a member like any other: it resolves the cluster through the
  # signature and so carries an eval edge to whatever provided it.
  # `componentsTargetTheCluster` would refuse it otherwise, and "resources
  # are different" is exactly the assumption that would make someone drop
  # that edge and find out from a lab rather than from here.
  testItIsAnOrdinaryMemberOfItsCluster = {
    expr = map (e: "${e.kind}:${e.from}->${e.to}") (
      lib.filter (e: e.from == "provisioned") plain.link.graph.edges
    );
    expected = [ "eval:provisioned->stub-cluster" ];
  };
}
