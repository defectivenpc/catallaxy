# lab-ca, alone.
#
# One root for the whole lab, and the two things worth pinning are the ones
# that used to be stated twice: where the certificate lands on the host, which
# the ingress mounts, and where the root lands in a cluster, which an issuer
# signs from. Both were strings in two files with nothing relating them.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  caWith =
    inputs:
    support.evalFloe {
      name = "lab-ca";
      inherit inputs;
    };

  r = caWith { };
  stepsOf = x: x.link.provides.lab-ca.step.steps;
in
lib.runTests {

  # The paths the CLI writes, declared here so the floe that mints the
  # certificate and the floe that serves it name them once between them.
  # `{{STATE_DIR}}` is expanded by the CLI and the `proxy` segment is
  # `host::state::PROXY_SERVICE` — the certificate lives in the ingress's
  # state directory because that is where the thing serving it looks.
  testItSaysWhereTheCertificateLands = {
    expr = {
      inherit (r.provides.labCa) pem caCert;
    };
    expected = {
      pem = "{{STATE_DIR}}/proxy/lab.pem";
      caCert = "{{STATE_DIR}}/proxy/ca.crt";
    };
  };

  # Where `import_lab_ca` puts the root in every cluster. It was a pair of
  # Rust string literals compared against a name `cert-manager` computed from
  # two of its own inputs, by an assertion that existed because nothing could
  # relate a Nix interpolation to a literal. The signature carries it now, so
  # the issuer reads the address instead of guessing it and being checked.
  testItSaysWhereTheRootLandsInACluster = {
    expr = r.provides.labCa.secret;
    expected = {
      namespace = "cert-manager";
      name = "lab-ca-ca-secret";
    };
  };

  # And both move together when they move, which is the point of them being
  # one answer: a lab pointing its issuer somewhere else changes what the
  # issuer reads, not what the CLI writes.
  testTheAddressIsOneAnswer = {
    expr =
      (caWith {
        secretName = "other-ca";
        secretNamespace = "pki";
      }).provides.labCa.secret;
    expected = {
      namespace = "pki";
      name = "other-ca";
    };
  };

  # The wildcard is `*.<zone>`, which is the lab's to say. Resolved rather
  # than taken as an input, because the zone is already a signature every
  # cluster resolves against and a second copy could disagree with it.
  testTheWildcardComesFromTheResolvedZone = {
    expr = (stepsOf r).cert-generate.params;
    expected = {
      zone = "stub.test";
    };
  };

  # Before every cluster is created, said as a condition: the services
  # bind-mount the certificate and `registry-setup` copies the root into each
  # cluster's `certs.d`, so it precedes creation too — and a floe has no name
  # for a cluster it is not in.
  testItPrecedesTheServicesAndEveryCluster = {
    expr = {
      before = (stepsOf r).cert-generate.before;
      beforeClusters = (stepsOf r).cert-generate.beforeClusters;
    };
    expected = {
      beforeClusters = "created";
      before = [ "optional:provides:lab/services" ];
    };
  };

  # Exactly one. Two roots means two chains, a client trusting one rejecting
  # the other, and nothing failing loudly enough to say why — so the linker
  # refuses the second rather than the lab picking.
  testThereIsOnlyEverOneRoot = {
    expr = r.def.singleton;
    expected = true;
  };
}
