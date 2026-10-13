# lab-network, alone.
#
# It answers three facts and emits two steps, and the interesting half is the
# steps — `remove-network` is the first caller of `afterClusters`, and the
# ordering it needs is the one that bites: `docker network rm` fails on a
# network a cluster's containers are still on.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  netWith =
    inputs:
    support.evalFloe {
      name = "lab-network";
      inputs = {
        name = "example";
        subnet = "172.20.0.0/16";
      }
      // inputs;
    };

  stepsOf = r: r.link.provides.lab-network.step.steps;
in
lib.runTests {

  # The three facts, answered once. They were threaded as inputs into the
  # proxy, the resolver, the egress and the zone — `network = lab.name` three
  # times and `server = lab.network.gateway` once — which is four places that
  # could be handed different answers.
  #
  # `gateway` is derived here and not given: the address after the subnet's
  # own was a required input whose only definition anywhere was that one
  # expression, written in the lab's option tree.
  testItAnswersTheNetworkOnce = {
    expr = (netWith { }).provides.network;
    expected = {
      name = "example";
      subnet = "172.20.0.0/16";
      gateway = "172.20.0.1";
    };
  };

  # `remove-network` is after every cluster is destroyed, said as a condition
  # because a floe has no name for a cluster it is not in. With no clusters in
  # the link there is nothing to be after, which is the shape of the
  # expansion: the lab turns the condition into one anchor each.
  testItSaysWhenToRemoveTheNetworkWithoutNamingACluster = {
    expr = (stepsOf (netWith { })).remove-network.afterClusters;
    expected = "destroyed";
  };

  # Both steps, and the tokens they publish — `setup-services` is after
  # `lab/network` by an anchor, so a missing `provides` here leaves it
  # unconstrained rather than failing.
  testItMakesAndUnmakesTheNetwork = {
    expr = lib.mapAttrs (_: s: s.provides) (stepsOf (netWith { }));
    expected = {
      docker-network-create = [ "lab/network" ];
      remove-network = [ "lab/network-removed" ];
    };
  };

  # A lab with nothing on the network — every cluster in a cloud, no host
  # services — creates none, and the step is simply not there rather than
  # being there and meaning nothing.
  #
  # The address facts stay true, which is why this is an input and not a
  # reason to leave the floe out: `lab-zone` requires them and is
  # unconditional, because a lab that runs no DNS still declares the zone its
  # routes hang off.
  testAnUnmanagedNetworkEmitsNoStepsAndStillAnswers = {
    expr = {
      steps = lib.attrNames (
        stepsOf (netWith {
          managed = false;
        })
      );
      gateway = (netWith { managed = false; }).provides.network.gateway;
    };
    expected = {
      steps = [ ];
      gateway = "172.20.0.1";
    };
  };

  # What the CLI parses before it runs anything, so it can refuse a lab whose
  # subnet overlaps one already on the host.
  testTheCreateStepCarriesTheRange = {
    expr = (stepsOf (netWith { })).docker-network-create.params;
    expected = {
      name = "example";
      subnet = "172.20.0.0/16";
      gateway = "172.20.0.1";
    };
  };
}
