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

        typeGen = import ./nix/generated-types.nix {
          inherit
            lib
            pkgs
            k8sSpecs
            crdSources
            ;
          inherit (packages') cata;
        };

        generatedTypes = typeGen.all;

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

        labArgs = {
          inherit
            lib
            pkgs
            floeCore
            kubelib
            ;
        };

        labs = import ./lib/lab.nix labArgs;

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

        kindPages = import ./nix/kind-docs.nix {
          inherit lib pkgs;
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
            kindPages
            ;
          inherit (packages') cata;
        };
        legacyPackages' = {
          inherit
            referencePages
            generatedTypes
            ;

          inherit (typeGen) floeTypes;

          inherit (labs)
            mkLab
            mkCluster
            mkFloes
            catallaxy
            floes
            ;

          # The distribution, rebuilt so that your floes' CRD types are in the
          # record your floes are defined against. `mkLab` and `catallaxy` from
          # here, not from the attributes above: those were built from the
          # built-in groups alone, and a custom resource whose group is missing
          # resolves to no schema and is checked for nothing.
          withFloes = extraFloes: import ./lib/lab.nix (labArgs // { inherit extraFloes; });
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
            upstream
            ;

          inherit (labs)
            mkLab
            mkFloes
            catallaxy
            floes
            ;
          inherit (legacyPackages') withFloes;
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
