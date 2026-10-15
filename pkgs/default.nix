# The CLI, the tools it shells out to, and the documents built from it.
{
  lib,
  pkgs,
  craneLib,
  rustToolchain,
  optionsJSON,
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

  optionDocs = import ./option-docs.nix {
    inherit
      lib
      pkgs
      cata
      optionsJSON
      ;
  };
  talks = import ./talks.nix { inherit lib pkgs; };
  docs = import ./docs.nix { inherit lib pkgs talks; };
in
{
  inherit
    tools
    cata
    cataWrapped
    optionDocs
    talks
    docs
    ;
}
