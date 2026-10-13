# The homelab with a DNS controller publishing into the lab's own zone.
#
# `external-dns` updates the resolver over RFC2136 with a TSIG key the server
# was told about, so a route gaining a hostname gains a record without anyone
# writing one. The key is lab-held material projected into the namespace the
# controller runs in — the only way a value a human authored reaches a
# cluster.
{
  lab,
  lib,
  floes,
  catallaxy,
  ...
}:

let
  clusters = import ../clusters.nix { inherit catallaxy floes lib; };
in
lab {
  name = "homelab.dns";

  core = clusters.coreWithDns { };

  units = {
    authored = floes.lab-secret-store { backend = "env"; };
    externaldns-tsig = floes.lab-authored-secret { keys.tsig-secret.generator = null; };
  };

  secretsEnvFile = "examples/labs/homelab/envs/dns.env";
}
