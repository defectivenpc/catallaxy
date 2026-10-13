# The lab's own certificate authority.
#
# One root for the whole lab: the ingress serves from it, every cluster's
# issuer signs from it, and every node trusts it. Two roots would mean two
# chains, and a client trusting one rejects the other with nothing failing
# loudly enough to say why — which is the failure this floe exists to make
# unrepresentable rather than to warn about.
#
# Placing it is the decision. It was `lab.proxy.tls.enable`, an option
# defaulting to true that no lab ever set, plus a `rootFromLab` boolean on
# `cert-manager` whose description read "set it exactly when
# `lab.proxy.tls.enable` is on" — a prose instruction with nothing checking
# it. A lab terminates TLS when this is in its link, and a cluster signs from
# the lab's root when it resolves this. One statement each.
#
# The paths mirror what `cli/src/host/pki.rs` writes, the way a k3d
# descriptor's `nodeConfigFrom` mirrors a state directory. `{{STATE_DIR}}` is
# expanded by the CLI, and the `proxy` segment is `host::state::PROXY_SERVICE`
# — the certificate lives in the ingress's state directory because that is
# where the thing serving it looks.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens wants;
in
floe.mkFloe {
  name = "lab-ca";
  summary = "One root for the lab: what the ingress serves from and every cluster's issuer signs from.";

  # Exactly one. Two roots is the thing this floe is for preventing, so the
  # linker refuses the second by name rather than the lab picking.
  singleton = true;

  inputs = {
    secretName = lib.mkOption {
      type = lib.types.str;
      default = "lab-ca-ca-secret";
      description = ''
        Secret the root lands in, in every cluster.

        `cli/src/host/pki.rs`'s `import_lab_ca` writes this name, so changing
        it here changes what a cluster's issuer reads and not what the CLI
        writes. It is an input so the address travels on the signature rather
        than being asserted against a literal in the floe that reads it.
      '';
    };

    secretNamespace = lib.mkOption {
      type = lib.types.k8sName or lib.types.str;
      default = "cert-manager";
      description = "Namespace that Secret lands in. Same contract as `secretName`.";
    };
  };

  # The wildcard it signs is `*.<zone>`, which is the lab's to say and no
  # floe's to invent.
  requires.zone = sigs.DNS_ZONE;

  provides.labCa = sigs.LAB_CA;
  provides.step = sigs.LAB_STEPS;

  body =
    { inputs, requires, ... }:
    {
      provides.labCa = {
        pem = "{{STATE_DIR}}/proxy/lab.pem";
        caCert = "{{STATE_DIR}}/proxy/ca.crt";
        secret = {
          namespace = inputs.secretNamespace;
          name = inputs.secretName;
        };
      };

      provides.step.steps.cert-generate = {
        kind = "cert-generate";
        description = "Mint the lab CA and a wildcard certificate for '*.${requires.zone.zone}'";
        provides = [ planTokens.lab.ingressCa ];

        before = [ (wants planTokens.lab.services) ];
        beforeClusters = "created";

        params = {
          inherit (requires.zone) zone;
        };
      };
    };
}
