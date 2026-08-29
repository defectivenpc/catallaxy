# The CLI and the tools it shells out to.
#
# The e2e runners, the option-docs generator and the book build are parked in
# `old-floes/pkgs/` and `old-floes/lib/docs/`: each of them evaluates the lab
# module tree, which is parked with the floe implementation it was written
# against. They come back as the platform is rebuilt on `lib/floe-core`.
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

in
{
  inherit
    tools
    cata
    cataWrapped
    ;
}
