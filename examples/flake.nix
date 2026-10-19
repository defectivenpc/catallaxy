{
  description = "catallaxy's example labs, as a flake that uses catallaxy";

  inputs = {
    catallaxy.url = "path:..";
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
        legacyPackages = {
          labs = lib.mapAttrs (_: l: l.cliConfig) corpus.labs;
          labPackages = lib.mapAttrs (_: l: l.package) all;
          labPlans = lib.mapAttrs (_: l: { inherit (l) deploymentPlan teardownPlan; }) all;

          labCliConfigs = import ../nix/cli-configs.nix {
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
