/*
  The labs used for testing e2e targeting.

      nix run ./examples#e2e-all

  A pass-through: for each lab, `cata lab up`, `cata lab verify`, `cata lab
  destroy`, in turn, stopping at the first failure. What a lab should do when
  it comes up is cata's to say, so anything this asserted in shell would be a
  second opinion kept in a second language.

  Eligibility is not derived. A lab is eligible when somebody has watched it
  come up and go away again on a laptop; that cannot be computed from the
  declaration, so it is written down. The list is baked into the script rather
  than read back out of this flake, so a run pointed at another checkout still
  knows its own set.
*/
{
  lib,
  pkgs,
  cataWrapped,
}:

let
  labs = [
    "crossplane.nop"
    "gitops.local"
    "homelab.dns"
    "homelab.local"
    "minimal.cilium"
    "minimal.local"
    "minimal.secrets"
    "minimal.talos"
    "minimal.tls"
  ];

  all = pkgs.writeShellApplication {
    name = "cata-e2e-all";

    runtimeInputs = [
      cataWrapped
      pkgs.nix
    ];

    text = ''
      set -euo pipefail

      flake="''${CATA_E2E_FLAKE:-./examples}"

      if [ "''${1:-}" = "--help" ]; then
        echo "usage: cata-e2e-all" >&2
        echo "" >&2
        echo "Stands each lab up, verifies it and destroys it, in turn," >&2
        echo "stopping at the first failure:" >&2
        printf '  %s\n' ${lib.concatStringsSep " " labs} >&2
        exit 64
      fi

      for lab in ${lib.concatStringsSep " " labs}; do
        echo "" >&2
        echo "=== $lab ===" >&2

        # Not an extra check: `cata` reads a lab's secrets from the
        # environment and only tells you which file would set them. Two labs
        # in the list name one, and the path is relative to the repository
        # root rather than to this flake.
        env_file=$(nix eval --raw "$flake#labs.\"$lab\".secrets.envFile" 2> /dev/null || true)
        if [ -n "$env_file" ]; then
          set -a
          # shellcheck disable=SC1090
          . "$flake/../$env_file"
          set +a
        fi

        cata --flake "$flake#$lab" lab up --infra
        cata --flake "$flake#$lab" lab verify
        cata --flake "$flake#$lab" lab destroy --infra
      done
    '';
  };
in
{
  packages = {
    e2e-all = all;
  };

  apps = {
    e2e-all = {
      type = "app";
      program = "${all}/bin/cata-e2e-all";
    };
  };
}
