# A cluster's platform: the things that have to be there before anything else
# in the cluster can be reached.

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

  collects.route = sigs.ROUTE_CLAIM;
  optional.labCa = sigs.LAB_CA;
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
