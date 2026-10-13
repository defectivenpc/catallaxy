# A cluster in a cloud, declared but never stood up here.
#
# `home` is local and runs the `doks` floe; `workload` is what that floe
# creates, and its claim is an `external-cluster` pointed at the kubeconfig
# `doks` published. The lab renders and snapshots without a token, which is
# the rung below actually calling DigitalOcean.
#
# A fixture is a lab with one environment, so it is one file: the definition
# and the instantiation together, and nothing to vary.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters/cloud.nix { inherit catallaxy floes lib; };
in
catallaxy.mkLabFloe
  {
    name = "cloud";
    summary = "A cluster in a cloud, declared but never stood up here.";

    units = _: {
      proxy = floes.lab-proxy { };
      egress = floes.lab-egress { };

      # One root for the lab: the ingress serves from it, and any cluster that
      # declares `optional.labCa` signs from it rather than minting a second.
      # Placing it is the whole decision — it was `lab.proxy.tls.enable`, an
      # option defaulting to true that no lab ever set.
      ca = floes.lab-ca { };

      # Where `doks` publishes the kubeconfig and the claim below reads it. One
      # store in the link, so both resolve it and only the key is written — and
      # it is written twice because the two clusters have different names and
      # neither can derive the other's.
      cloud = floes.lab-secret-store { backend = "env"; };
    };

    clusters = _: {
      home = {
        floe = clusters.home { };
        claim = floes.k3d-cluster { };
      };

      workload = {
        floe = clusters.workload { };
        claim = floes.external-cluster {
          context = "cata-cloud-workload";
          madeBy = "opentofu, from the 'doks' floe on 'home'";
          podSubnet = "10.244.0.0/16";
          serviceSubnet = "10.245.0.0/16";
          assignsLoadBalancers = true;
          kubeconfigKey = "clusters/workload/kubeconfig";
        };
      };
    };
  }
  {
    name = "cloud";
    zone = "cloud.test";

    # Both sides of the kubeconfig: `doks` in `home` publishes into it and
    # `workload`'s claim reads it back. One line rather than two `.bind`s,
    # because with one store in the lab there is nothing to tell apart — what
    # the default supplies is the *decision* to wire an optional hole at all.
    defaults.LAB_SECRET_STORE = "cloud";
  }
