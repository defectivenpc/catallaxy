{
  description = "catallaxy: declarative Kubernetes platform management";

  # The platform is built on the floe interface of RFC 0001 (`lib/floe-core`).
  # Two earlier implementations preceded it; what they cost is recorded in
  # `docs/prior-implementations.md`, and the code is in git.
  #
  # `labs` and `labPackages` are the two attribute paths `cata` resolves. The
  # CLI is untouched and its contract is unchanged.

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

        # Fixture labs render and snapshot but never run, so they are in
        # `labPackages` and not in `labs`.
        exampleLabs = labs.discoverLabs;
        fixtureLabs = labs.discoverFixtures;
        labDefs = exampleLabs // fixtureLabs;

        # One binding, two readers: the flake output the e2e runner evaluates,
        # and the check that pins what it says. Computing it twice would let
        # them disagree about the very thing one exists to check.
        e2eLabs = lib.mapAttrs (_: l: l.config.lab.out.selfContained) exampleLabs;
      in
      {
        legacyPackages = {
          charts = cataCharts;

          # The two the CLI resolves, and the only two.
          labs = lib.mapAttrs (_: l: l.config.lab.out.cliConfig) exampleLabs;
          labPackages = lib.mapAttrs (_: l: l.config.lab.out.package) labDefs;

          # The intermediate the lab is lowered from, for reading by hand.
          clusters = lib.mapAttrs (_: l: lib.mapAttrs (_: c: c.out) l.config.lab.clusters) labDefs;

          # What the e2e runner builds its matrix from. Example labs only:
          # a fixture exists to be rendered and checked, never stood up.
          inherit e2eLabs;

          # What `refresh-digests` iterates and what the digest checks cover —
          # everything that renders, fixtures included.
          digestLabs = lib.attrNames labDefs;

          # Both plans per lab, for `cata lab plan --from-file`. A fixture is
          # not in `labs`, so the CLI cannot resolve one by name — and the
          # snapshot check compares fixtures too, so there has to be a way to
          # produce the same text for them.
          labPlans = lib.mapAttrs (_: l: {
            inherit (l.config.lab.out) deploymentPlan teardownPlan;
          }) labDefs;
        };

        packages = {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;

          inherit (packages')
            e2e
            e2e-all
            refresh-digests
            refresh-plans
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

        apps.refresh-digests = {
          type = "app";
          program = "${packages'.refresh-digests}/bin/refresh-digests";
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
          inherit
            self
            lib
            pkgs
            treefmtEval
            ;
          packages = packages';
          inherit labDefs;

          # A check that a *wrong* lab is refused has to build one, and only
          # `mkLab` can: the refusal is an assertion inside the module tree,
          # so there is nothing to inspect without evaluating it.
          inherit (labs) mkLab;
          inherit e2eLabs;
        };
      }
    );
}
