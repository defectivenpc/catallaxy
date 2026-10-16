# The labs used for testing e2e targeting. `nix run ./examples#e2e-all`
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
