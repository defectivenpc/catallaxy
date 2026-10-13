# A cluster's platform: the things that have to be there before anything else
# in the cluster can be reached.
#
# This was `homelab`'s `platform` closure, then a preset, and is now what both
# were standing in for: a floe whose units are other floes. Backpack's
# `include`, which the floe interface has since gained, so the private
# mechanism it needed is gone.
#
# **The claim is open.** Nothing in here brings a cluster into existence, so
# `requires.cluster` is left for whoever places this to answer — which is what
# makes one assembly serve a k3d cluster here and a Talos or managed one
# elsewhere. It replaces the `provisioner` input, which smuggled a floe
# instance through a surface that deep-forces its arguments, and is why the
# preset needed three structural inputs the type checker could not see.
#
# `requires.zone` is open for the same reason, one level further out: the zone
# is a fact the lab holds and no cluster can derive.
#
# Apps go beside it, not into it. What crosses out of it is `exports`, and
# every signature an app resolves against has to be named there — an inclusion
# exports nothing by default, which is the half of sealing that makes this an
# interface rather than an arrangement of files.
{
  floe,
  lib,
  sigs,
  floes,
  ...
}:

floe.mkFloe {
  name = "standard-cluster";
  summary = "CRDs, an issuer, trust, in-cluster DNS, a gateway and a secret generator.";

  inputs = {
    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the gateway terminates TLS.";
    };

  };

  requires = {
    cluster = sigs.KUBERNETES_CLUSTER;
    zone = sigs.DNS_ZONE;
  };

  # Declared here as well as on the gateway inside, because a collection is
  # per link: the workloads that claim a hostname sit *beside* this assembly,
  # not in it. The linker injects one unit per contributor, so the gateway
  # inside sees the same fan-in the parent did. ADR 0004.
  collects.route = sigs.ROUTE_CLAIM;

  # The lab's root, when the lab holds one and placed this where it can see
  # it. Declared here as well as on the `cert-manager` inside, because a hole
  # an inclusion does not declare is a hole the parent cannot fill — it was a
  # `rootFromLab` bool threaded down two levels.
  optional.labCa = sigs.LAB_CA;

  # Declared here as well, for the other reason: the claim that answers it is
  # a unit *beside* this assembly, placed by whoever placed this. The gateway
  # inside takes the same optional hole, and the linker injects the provider
  # inward once this level resolves it.
  optional.edge = sigs.CLUSTER_EDGE;

  provides = {
    gateway = sigs.API_GATEWAY;

    exposure = sigs.HOST_EXPOSURE;
    gatewayApi = sigs.GATEWAY_API;
    issuance = sigs.X509_ISSUANCE;
    webhook = sigs.X509_WEBHOOK;
    generation = sigs.SECRET_GENERATION;
    trust = sigs.TRUST_BUNDLE;
  };

  exports = {
    gateway = "gateway/gateway";
    exposure = "gateway/exposure";
    gatewayApi = "gateway-api/gatewayApi";
    issuance = "cert-manager/issuance";
    webhook = "cert-manager/webhook";
    generation = "external-secrets/generation";
    trust = "trust-manager/trust";
  };

  units =
    { inputs, ... }:
    {
      gateway-api = floes.gateway-api-crds { };

      cert-manager = floes.cert-manager { };

      trust-manager = floes.trust-manager { };

      coredns-zone = floes.coredns-zone { };

      gateway = floes.gateway { tlsEnable = inputs.tls; };

      external-secrets = floes.external-secrets { };
    };
}
