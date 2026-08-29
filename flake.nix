{
  description = "catallaxy: declarative Kubernetes platform management";

  # The platform is built on the floe interface of RFC 0001 (`lib/floe-core`).
  # The two earlier floe implementations and everything written against them
  # are parked in `old-floes/`, which nothing here imports and which is not
  # expected to evaluate. See `old-floes/README.md`.
  #
  # `labs` and `labPackages` are the two attribute paths `cata` resolves, and
  # they carry one lab so far. The CLI is untouched and its contract is
  # unchanged.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    nix-kube-generators.url = "github:farcaller/nix-kube-generators";

    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-kube-generators,
      crane,
      rust-overlay,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        treefmtEval = treefmt-nix.lib.evalModule pkgs (
          import ./nix/treefmt.nix { inherit lib rustToolchain; }
        );

        kubelib = nix-kube-generators.lib { inherit pkgs; };
        cataCharts = import ./lib/charts.nix { inherit lib pkgs kubelib; };
        k8sSpecs = import ./lib/k8s-specs.nix { inherit lib pkgs cataCharts; };

        packages' = import ./pkgs {
          inherit
            lib
            pkgs
            craneLib
            rustToolchain
            ;
        };

        labs = import ./lib/lab.nix {
          inherit
            lib
            pkgs
            cataCharts
            k8sSpecs
            ;
          examplesPath = ./examples/labs;
        };

        labDefs = labs.discoverLabs;
      in
      {
        legacyPackages = {
          charts = cataCharts;

          # The two the CLI resolves, and the only two.
          labs = lib.mapAttrs (_: l: l.config.lab.out.cliConfig) labDefs;
          labPackages = lib.mapAttrs (_: l: l.config.lab.out.package) labDefs;

          # The intermediate the lab is lowered from, for reading by hand.
          clusters = lib.mapAttrs (_: l: lib.mapAttrs (_: c: c.out) l.config.lab.clusters) labDefs;
        };

        packages = {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;
        };

        apps.default = {
          type = "app";
          program = "${packages'.cataWrapped}/bin/cata";
        };

        devShells.default = import ./nix/devshell.nix {
          inherit pkgs rustToolchain;
          packages = packages';
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = import ./nix/checks {
          inherit
            self
            lib
            pkgs
            treefmtEval
            ;
          packages = packages';
          inherit labDefs;
        };
      }
    );
}
