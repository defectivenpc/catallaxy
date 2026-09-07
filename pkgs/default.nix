# The CLI, the tools it shells out to, and the runners that test a whole lab.
#
# The option-docs generator is still parked; its splicer survives as
# `cata-build docs render`.
{
  lib,
  pkgs,
  craneLib,
  rustToolchain,
}:

let
  tools =
    with pkgs;
    [
      talosctl
      k3d
      kubectl
      kapp
      kyverno-chainsaw
      kubernetes-helm
      jq
      yq-go
      docker-client
      coreutils
      openssl
      sops
      age
      crane
      gzip
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      pkgs.nssTools
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      pkgs.colima
    ];

  cata = import ./cli.nix {
    inherit
      lib
      pkgs
      craneLib
      rustToolchain
      ;
  };

  cataWrapped = pkgs.writeShellApplication {
    name = "cata";
    runtimeInputs = tools ++ [
      cata
      pkgs.nix
    ];
    text = ''
      export CATALLAXY_SYSTEM_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      exec ${cata}/bin/cata "$@"
    '';
  };

  e2e = import ./e2e.nix { inherit lib pkgs cataWrapped; };
  e2e-all = import ./e2e-all.nix { inherit lib pkgs e2e; };
  cloud-reap = import ./cloud-reap.nix { inherit lib pkgs; };
  e2e-cloud = import ./e2e-cloud.nix { inherit lib pkgs cataWrapped; };
  refresh-digests = import ./refresh-digests.nix { inherit lib pkgs; };
  refresh-cli-configs = import ./refresh-cli-configs.nix { inherit lib pkgs; };
  refresh-floe-docs = import ./refresh-floe-docs.nix { inherit lib pkgs; };
  docs = import ./docs.nix { inherit lib pkgs; };
  refresh-plans = import ./refresh-plans.nix {
    inherit lib pkgs;
    cata = cataWrapped;
  };

in
{
  inherit
    tools
    cata
    cataWrapped
    e2e
    e2e-all
    e2e-cloud
    cloud-reap
    refresh-digests
    refresh-cli-configs
    refresh-floe-docs
    refresh-plans
    docs
    ;
}
