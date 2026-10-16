# Every floe in the catalogue, enabled somewhere.
#
# The example labs are labs someone would build. This is not: it exists
# because a floe no lab renders is a floe whose declarations nothing checks —
# its images are never scraped, its bundles never laid out, its signature
# never resolved against a real peer. A migration that leaves a floe
# unexercised has not finished with it.
#
# It renders and snapshots like any other lab and never enters the e2e set,
# which is what makes it the cheap place to keep this honest.
#
# Grouped into clusters only where floes cannot share one. Right now they all
# can, so there is one; a second appears when something claims a capability
# another floe already holds.
{
  lib,
  floes,
  catallaxy,
  ...
}:

let
  zone = "every-floe.test";

  clusters = import ./clusters/every-floe.nix {
    inherit
      catallaxy
      floes
      lib
      zone
      ;
  };
in
catallaxy.mkLabFloe
  {
    name = "every-floe";
    summary = "Every floe in the catalogue, enabled somewhere.";

    units = _: {
      # Three stores and two secrets, every one a unit of the lab's link.
      # Nothing resolves by itself at this width, which is the point of having
      # it here: each secret binds its store and the cluster binds each secret.
      authored = floes.lab-secret-store { backend = "sops"; };
      runtime = floes.lab-secret-store { backend = "vault"; };
      knot = floes.lab-secret-store { backend = "env"; };

      vault-credential =
        (floes.lab-authored-secret {
          keys.token = {
            generator = "hex";
            length = 32;
          };
        }).bind
          { labStore = "authored"; };

      externaldns-tsig = (floes.lab-authored-secret { keys.tsig-secret.generator = null; }).bind {
        labStore = "knot";
      };
    };

    clusters = _: {
      core = {
        floe = (clusters.core { }).bind {
          labStore = "runtime";
          vaultCredential = "vault-credential";
          tsigSecret = "externaldns-tsig";
        };
        provisioner = floes.k3d-cluster { };
      };
    };
  }
  {
    name = "every-floe";
    inherit zone;

    secretsEnvFile = "examples/labs/tests/every-floe.env";

    # Cilium is in the cluster, and the provisioner starting without flannel is
    # a separate decision. This is it.
    defaults.CNI_BOOTSTRAP = "core";
  }
