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
        cataCharts = import ./lib/charts.nix { inherit lib pkgs kubelib; };
        k8sSpecs = import ./lib/k8s-specs.nix { inherit lib pkgs cataCharts; };

        floePaths = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ./floes));

        floeCrds = import ./floes/crds.nix { inherit lib; };
        crdSources = lib.mapAttrs (_: f: f { inherit cataCharts k8sSpecs; }) floeCrds.sources;

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
            cataCharts
            k8sSpecs
            ;
          examplesPath = ./examples/labs;
        };

        exampleLabs = labs.discoverLabs;
        fixtureLabs = labs.discoverFixtures;
        labDefs = exampleLabs // fixtureLabs;

        e2e = import ./nix/e2e.nix {
          inherit lib pkgs;
          inherit (packages') cataWrapped;
        };

        cliConfigs = import ./nix/cli-configs.nix { inherit lib pkgs labDefs; };

        floePages = import ./nix/floe-docs.nix {
          inherit
            lib
            pkgs
            labDefs
            cataCharts
            k8sSpecs
            ;
          inherit (labs) catallaxy;
          floeSet = floePaths;
        };

        signaturePages = import ./nix/signature-docs.nix {
          inherit
            lib
            pkgs
            cataCharts
            k8sSpecs
            ;
          inherit (labs) catallaxy;
          floeSet = floePaths;
        };

        standaloneClusters = lib.mapAttrs (
          name: path:
          labs.mkCluster (
            {
              inherit name;
            }
            // import path {
              inherit lib pkgs;
              inherit (labs) catallaxy floes;
            }
          )
        ) { minimal = ./examples/clusters/minimal.nix; };

        referencePages = import ./pkgs/reference-pages.nix {
          inherit
            lib
            pkgs
            floePages
            signaturePages
            ;
          inherit (packages') cata;
        };
        labOutputs = import ./nix/lab-outputs.nix {
          inherit
            lib
            pkgs
            labDefs
            exampleLabs
            ;
        };

        legacyPackages' = labOutputs // {
          inherit
            allocations
            standaloneClusters
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

          charts = cataCharts;
          labCliConfigs = cliConfigs;
        };

        flakePackages = e2e.packages // {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;

          inherit (packages') talks docs;
        };

      in
      {
        legacyPackages = legacyPackages';

        packages = flakePackages;

        apps = e2e.apps // {
          default = {
            type = "app";
            program = "${packages'.cataWrapped}/bin/cata";
          };
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
            cataCharts
            k8sSpecs
            treefmtEval
            labDefs
            exampleLabs
            standaloneClusters
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
