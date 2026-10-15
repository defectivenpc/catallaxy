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

        e2eLabs = [
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

        cloudE2eLabs = {
          "cloud" = [ "DIGITALOCEAN_TOKEN" ];
          "every-floe" = [ "DIGITALOCEAN_TOKEN" ];

          "provisions" = [ ];
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
        legacyPackages' = {
          inherit
            allocations
            standaloneClusters
            e2eLabs
            cloudE2eLabs
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
          digestLabs = lib.attrNames labDefs;

          labs = lib.mapAttrs (_: l: l.cliConfig) exampleLabs;
          labPackages = lib.mapAttrs (_: l: l.package) labDefs;

          clusters = lib.mapAttrs (
            _: l:
            lib.mapAttrs (
              name: c:
              pkgs.runCommand "cluster-${name}" { } ''
                mkdir -p $out
                cp ${pkgs.writeText "cluster.json" (builtins.toJSON c.spec)} $out/cluster.json
                ln -s ${c.manifests} $out/manifests
              ''
            ) l.clusters
          ) labDefs;

          clusterPictures = lib.mapAttrs (_: l: lib.mapAttrs (_: c: c.out) l.clusters) labDefs;

          labPlans = lib.mapAttrs (_: l: {
            inherit (l) deploymentPlan teardownPlan;
          }) labDefs;
        };

      in
      {
        legacyPackages = legacyPackages';

        packages = {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;

          inherit (packages')
            e2e
            e2e-all
            e2e-cloud
            cloud-reap
            refresh-digests
            refresh-cli-configs
            refresh-docs
            refresh-allocations
            refresh-generated-types
            refresh-plans
            talks
            docs
            ;
        };

        apps.default = {
          type = "app";
          program = "${packages'.cataWrapped}/bin/cata";
        };

        # `nix run .#e2e` with no argument prints the eligible set and why the
        # rest are not, which is the intended way to find out.
        apps.e2e = {
          type = "app";
          program = "${packages'.e2e}/bin/cata-e2e";
        };

        apps.e2e-all = {
          type = "app";
          program = "${packages'.e2e-all}/bin/cata-e2e-all";
        };

        # Spends money. Never in `nix flake check`, never on a PR.
        apps.e2e-cloud = {
          type = "app";
          program = "${packages'.e2e-cloud}/bin/cata-e2e-cloud";
        };

        apps.cloud-reap = {
          type = "app";
          program = "${packages'.cloud-reap}/bin/cata-cloud-reap";
        };

        apps.refresh-digests = {
          type = "app";
          program = "${packages'.refresh-digests}/bin/refresh-digests";
        };

        apps.refresh-cli-configs = {
          type = "app";
          program = "${packages'.refresh-cli-configs}/bin/refresh-cli-configs";
        };

        apps.refresh-docs = {
          type = "app";
          program = "${packages'.refresh-docs}/bin/refresh-docs";
        };

        apps.refresh-allocations = {
          type = "app";
          program = "${packages'.refresh-allocations}/bin/refresh-allocations";
        };

        apps.refresh-generated-types = {
          type = "app";
          program = "${packages'.refresh-generated-types}/bin/refresh-generated-types";
        };

        apps.refresh-plans = {
          type = "app";
          program = "${packages'.refresh-plans}/bin/refresh-plans";
        };

        devShells.default = import ./nix/devshell.nix {
          inherit pkgs rustToolchain;
          packages = packages';
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = import ./nix/checks {
          legacyPackages = legacyPackages';
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
