{
  description = "catallaxy: declarative Kubernetes platform management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-kube-generators.url = "github:farcaller/nix-kube-generators";
    floes.url = "path:/home/whitehead/workspace/praxiotic/floes";
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
      floes,
      crane,
      rust-overlay,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      floeCore = floes.mkFloeLib lib;
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
        k8sSpecs = import ./lib/k8s-specs.nix { inherit lib pkgs; };

        floePaths = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ./floes));

        upstream = import ./lib/upstream.nix { inherit lib pkgs kubelib; };

        floeCrds = import ./lib/floe-crds.nix { inherit lib; } { floeSet = floePaths; };
        crdSources = lib.mapAttrs (_: f: f upstream) floeCrds.sources;

        generatedTypes = import ./nix/generated-types.nix {
          inherit
            lib
            pkgs
            k8sSpecs
            crdSources
            ;
          inherit (packages') cata;
        };

        packages' = import ./pkgs {
          inherit
            lib
            pkgs
            craneLib
            rustToolchain
            ;

          optionsJSON = import ./nix/option-docs.nix { inherit lib pkgs; };
        };

        allocations = import ./nix/allocations.nix { inherit lib pkgs labDefs; };

        labs = import ./lib/lab.nix {
          inherit
            lib
            pkgs
            floeCore
            kubelib
            ;
        };

        # The example corpus is this flake's test input, not its output.
        # `examples/flake.nix` is what exposes it, as a consumer would.
        corpus = import ./examples/labs.nix {
          inherit lib;
          cata = labs;
        };

        exampleLabs = corpus.labs;
        labDefs = corpus.labs // corpus.fixtures;

        cliConfigs = import ./nix/cli-configs.nix { inherit lib pkgs labDefs; };

        floePages = import ./nix/floe-docs.nix {
          inherit lib pkgs labDefs;
          inherit (labs) catallaxy mkFloes;
          floeSet = floePaths;
        };

        signaturePages = import ./nix/signature-docs.nix {
          inherit lib pkgs;
          inherit (labs) catallaxy mkFloes;
          floeSet = floePaths;
        };

        referencePages = import ./pkgs/reference-pages.nix {
          inherit
            lib
            pkgs
            floePages
            signaturePages
            ;
          inherit (packages') cata;
        };
        legacyPackages' = {
          inherit
            referencePages
            generatedTypes
            ;

          inherit (labs)
            mkLab
            mkCluster
            mkFloes
            catallaxy
            floes
            ;
          inherit (packages') optionDocs;
        };

        flakePackages = {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;

          inherit (packages') talks docs;
        };

      in
      {
        legacyPackages = legacyPackages';

        packages = flakePackages;

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
          legacyPackages = legacyPackages';
          inherit flakePackages;
          inherit
            self
            lib
            pkgs
            floeCore
            k8sSpecs
            treefmtEval
            labDefs
            exampleLabs
            allocations
            cliConfigs
            referencePages
            generatedTypes
            floeCrds
            ;

          inherit (labs)
            mkLab
            mkFloes
            catallaxy
            floes
            ;
          inherit (packages') optionDocs;

          packages = packages';
        };
      }
    )
    // {
      templates.consumer = {
        path = ./templates/consumer;
        description = "A lab in your own flake, with catallaxy as an input.";
      };
    };
}
