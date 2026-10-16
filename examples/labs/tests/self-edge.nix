# Two clusters, one of which the lab does not front.
#
# `edge` says so by exporting no exposure: the resolver answers for none of
# its hostnames, the ingress has no backend for them, and `cata lab verify`
# finds them absent from the host map and says it skipped them. That is the
# case a managed cluster in a cloud is in, exercised here without a cloud.
#
# One statement, read by three things. It used to be two — the export, plus a
# `lab.edges.edge.mode` override the document carried for `verify` — and
# keeping those in step was the deployer's job.
#
# `core` is routed normally, so both paths are live in one lab and a change
# that breaks either is caught.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ./clusters/self-edge.nix { inherit catallaxy floes lib; };

  provisionerFor = podSubnet: serviceSubnet: floes.k3d-cluster { inherit podSubnet serviceSubnet; };
in
catallaxy.mkLabFloe
  {
    name = "self-edge";
    summary = "Two clusters, one of which the lab does not front.";

    units = _: {
      proxy = floes.lab-proxy { };
      egress = floes.lab-egress { };

      # One root for the lab: the ingress serves from it, and any cluster that
      # declares `optional.labCa` signs from it rather than minting a second.
      # Placing it is the whole decision — it was `lab.proxy.tls.enable`, an
      # option defaulting to true that no lab ever set.
      ca = floes.lab-ca { };

      dns = floes.lab-dns { };
    };

    clusters = _: {
      core = {
        floe = clusters.mk {
          name = "core";
          fronted = true;
        } { };
        provisioner = provisionerFor "10.244.0.0/16" "10.96.0.0/12";
      };

      # Its own edge, which it says by exporting no exposure: the lab has
      # nothing to answer for it, so the resolver emits no record and the proxy
      # routes nothing to it.
      edge = {
        floe = clusters.mk {
          name = "edge";
          fronted = false;
        } { };
        provisioner = provisionerFor "10.245.0.0/16" "10.112.0.0/12";
      };
    };
  }
  {
    name = "self-edge";
    zone = "self-edge.test";
  }
