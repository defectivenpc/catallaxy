{
  description = "catallaxy's example labs, as a flake that uses catallaxy";

  inputs = {
    catallaxy.url = "path:..";

    # Not independent pins. The root flake's checks hold these labs to
    # byte-exact digests, and a second nixpkgs would render a different tree
    # from the one those digests were taken over.
    nixpkgs.follows = "catallaxy/nixpkgs";
    flake-utils.follows = "catallaxy/flake-utils";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      catallaxy,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        lib = nixpkgs.lib;
        pkgs = nixpkgs.legacyPackages.${system};
        cata = catallaxy.legacyPackages.${system};

        corpus = import ./labs.nix { inherit lib cata; };

        all = corpus.labs // corpus.fixtures;

        e2e = import ./e2e.nix {
          inherit lib pkgs;
          cataWrapped = catallaxy.packages.${system}.cata;
        };
      in
      {
        # `labs` and `labPackages` are the two names `cata --flake` resolves,
        # at exactly the paths a consumer flake puts them.
        #
        # Fixtures are in `labPackages` and `labPlans` but not in `labs`: a
        # fixture is not a lab anybody would run, and `cata lab list` must not
        # offer one. They are here so that refreshing a fixture's committed
        # digest is `nix build ./examples#labPackages."<fixture>"`, the same
        # command as for a lab.
        legacyPackages = {
          labs = lib.mapAttrs (_: l: l.cliConfig) corpus.labs;
          labPackages = lib.mapAttrs (_: l: l.package) all;
          labPlans = lib.mapAttrs (_: l: { inherit (l) deploymentPlan teardownPlan; }) all;

          # The two committed oracles that are refreshed wholesale rather than
          # one lab at a time. The root flake's checks compute both from this
          # same corpus; these exist so a refresh is one build.
          labCliConfigs = import ../nix/cli-configs.nix {
            inherit lib pkgs;
            labDefs = all;
          };

          allocations = import ../nix/allocations.nix {
            inherit lib pkgs;
            labDefs = all;
          };
        };

        packages = e2e.packages;
        apps = e2e.apps;

        devShells.default = catallaxy.devShells.${system}.default;
      }
    );
}
