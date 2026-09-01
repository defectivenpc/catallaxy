# lab-dns, alone.
#
# The one floe whose whole content is a fact the lab holds, so what is worth
# pinning is that the three inputs reach the server block and nothing else
# does — a hardcoded zone or port here resolves for whoever wrote it and for
# nobody standing a second lab up beside theirs.
{ lib, pkgs }:

let
  support = import ./support.nix { inherit lib pkgs; };

  r = support.evalFloe {
    name = "lab-dns";
    inputs = {
      zone = "example.test";
      server = "172.20.0.1";
      port = 5399;
    };
  };

  bundle = r.bundles.coredns;
  configMap = bundle.resources.coredns-custom;
in
lib.runTests {

  # k3s's CoreDNS imports `/etc/coredns/custom/*.server` out of a ConfigMap
  # under this exact name, so the name is contract with k3s rather than a
  # label. The key becomes the filename.
  testItIsOneConfigMapCorednsAlreadyMounts = {
    expr = {
      inherit (configMap) apiVersion kind;
      inherit (configMap.metadata) name namespace;
      keys = lib.attrNames configMap.data;
    };
    expected = {
      apiVersion = "v1";
      kind = "ConfigMap";
      name = "coredns-custom";
      namespace = "kube-system";
      keys = [ "lab.server" ];
    };
  };

  # All three inputs, in the one place they are read. A pod resolving
  # `podinfo.example.test` gets here or gets NXDOMAIN from a resolver that
  # never heard of the lab.
  testTheServerBlockCarriesTheZoneTheServerAndThePort = {
    expr = configMap.data."lab.server";
    expected = ''
      example.test:53 {
          errors
          cache 30
          forward . 172.20.0.1:5399
      }
    '';
  };

  # `kube-system` is where CoreDNS runs, and it exists before any floe does.
  # A floe creating it would be claiming a namespace k3s owns.
  testItCreatesNoNamespace = {
    expr = bundle.createNamespaces;
    expected = [ ];
  };

  # There is no workload here and no status to poll. Waiting for a rollout
  # that cannot happen is how a wave stalls on a ConfigMap.
  testAConfigMapHasNoRolloutToWaitOn = {
    expr = bundle.awaitRollout;
    expected = false;
  };

  # It runs nothing, so `imagesComplete` is a true claim rather than an
  # unanswered one, and the images check has nothing to find.
  testItRunsNothingAndSaysSo = {
    expr = {
      inherit (r.component) imagesComplete;
      images = r.cluster.images;
    };
    expected = {
      imagesComplete = true;
      images = { };
    };
  };

  # It dials the lab's resolver on the input port, and says so — a floe
  # silent about its network is named by the elaborator, and this one must
  # not be among them.
  testItDeclaresTheEgressItActuallyNeeds = {
    expr = {
      undeclared = r.cluster.undeclaredNetwork;
      ports = (lib.head r.component.network.egress.cidrs).ports;
    };
    expected = {
      undeclared = [ ];
      ports = [
        {
          port = 5399;
          protocol = "UDP";
        }
        {
          port = 5399;
          protocol = "TCP";
        }
      ];
    };
  };

  # It requires the cluster and nothing else, and declares no ordering.
  # Whatever wave it lands in is derived.
  testItDeclaresNoOrdering = {
    expr = bundle.needs;
    expected = [ ];
  };
}
