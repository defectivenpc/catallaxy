# A cluster with the things a cluster needs, parameterised by what runs on it.
#
# This is `homelab`'s `platform` closure, which two labs and a fixture had each
# grown a private copy of. As a preset it has an interface: what it provides is
# declared and checked against its members, `floe-docs` renders it, and another
# lab can use it without copying a function.
#
# The provisioner is an input and has no default. A preset that shipped one
# would quietly make every cluster k3d, which is the "works on my laptop"
# failure — and all three provisioners answer `KUBERNETES_CLUSTER`, so taking
# it as a parameter is what makes one preset serve local, Talos and external
# clusters alike.
#
# Apps go beside it, not into it. Expansion is flat, so an app requiring
# `API_GATEWAY` resolves against the gateway below exactly as if the lab had
# written both by hand:
#
#     lab.clusters.app.floes = {
#       platform = presets.standard-cluster { provisioner = floes.k3d-cluster { }; };
#       myapp    = floes.myapp { };
#     };
{
  catallaxy,
  lib,
  sigs,
  floes,
  ...
}:

catallaxy.mkPreset {
  name = "standard-cluster";
  summary = "A cluster with CRDs, an issuer, trust, in-cluster DNS, a gateway and a secret generator.";

  inputs = {
    provisioner = lib.mkOption {
      type = lib.types.raw;
      description = ''
        The floe that brings the cluster into existence — any floe providing
        `KUBERNETES_CLUSTER`. No default: which kind of cluster this is, is the
        one thing a preset must not decide for you.
      '';
    };

    tls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the gateway terminates TLS.";
    };

    rootFromLab = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Sign from the lab's CA rather than a root minted in this cluster. What
        lets one ingress terminate for several clusters with one certificate.
      '';
    };
  };

  # Checked against the members below, not merely asserted — this list was
  # wrong when it was first written (it claimed SECRET_STORE, which none of
  # these provides) and the check said so at the moment of instantiation.
  provides = {
    cluster = sigs.KUBERNETES_CLUSTER;
    gateway = sigs.API_GATEWAY;
    gatewayApi = sigs.GATEWAY_API;
    issuance = sigs.X509_ISSUANCE;
    generation = sigs.SECRET_GENERATION;
    trust = sigs.TRUST_BUNDLE;
  };

  members = inputs: {
    cluster = inputs.provisioner;

    gateway-api = floes.gateway-api-crds { };

    cert-manager = floes.cert-manager { inherit (inputs) rootFromLab; };

    # The other half of one root: cert-manager signs from the lab CA, and this
    # puts that CA in a ConfigMap in every namespace so a workload can *verify*
    # what the lab signed. A floe dialling an in-lab HTTPS endpoint fails x509
    # without it, and the error names a certificate rather than what is absent.
    trust-manager = floes.trust-manager { };

    # So a pod resolves `*.<zone>` too: its resolver is the cluster's CoreDNS,
    # which has never heard of the lab.
    lab-dns = floes.lab-dns { };

    gateway = floes.gateway { tlsEnable = inputs.tls; };

    # Credentials minted in the cluster rather than written into a rendered
    # manifest, which needs a generator wherever it happens.
    external-secrets = floes.external-secrets { };
  };
}
