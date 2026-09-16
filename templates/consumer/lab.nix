# Your topology.
#
# `floes` is catallaxy's set, handed in by `mkLab`. `myFloes` is yours,
# handed in by the flake — a floe is a function, not a module to import, so
# it reaches the lab as an ordinary argument.
{ myFloes }:

{
  lib,
  floes,
  ...
}:

{
  lab.name = lib.mkDefault "my-platform";
  lab.dns.zone = lib.mkDefault "example.test";

  lab.clusters.app.floes = {
    cluster = floes.k3d-cluster { };

    gateway-api = floes.gateway-api-crds { };

    # The gateway requires X509_ISSUANCE outright, so every cluster with a
    # gateway has an issuer even when nothing terminates TLS.
    cert-manager = floes.cert-manager { };

    gateway = floes.gateway { };

    hello = myFloes.hello-world { };
  };
}
