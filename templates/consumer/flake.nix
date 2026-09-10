{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    catallaxy.url = "github:onepunchtech/catallaxy";
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
        cata = catallaxy.legacyPackages.${system};

        myFloes = cata.mkFloes (import ./floes);

        lab = cata.mkLab {
          modules = [ (import ./lab.nix { inherit myFloes; }) ];
        };
      in
      {
        legacyPackages = {
          labs."my-platform" = lab.config.lab.out.cliConfig;
          labPackages."my-platform" = lab.config.lab.out.package;
        };

        # Rendering the lab touches every option, so an unmet `requires`, a
        # bad `exports` read, or a broken anchor fails in CI rather than at
        # `lab up`.
        checks.lab-renders = lab.config.lab.out.package;
      }
    );
}
