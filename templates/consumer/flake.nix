{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Point this at a checkout to try a change before it is published:
    #   nix flake lock --override-input catallaxy /path/to/catallaxy
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
        # One lab, so this shell can point at it without guessing. `kubectl`
        # then reaches the lab's clusters with no `--context` and no export —
        # a lab's clusters live in its own kubeconfig rather than in
        # `~/.kube/config`, so that a lab cannot clobber a cluster you depend
        # on.
        #
        # `cata --flake .#my-platform lab env` is the same thing for a shell
        # you did not start here, and it sets the CA variables too.
        devShells.default = nixpkgs.legacyPackages.${system}.mkShell {
          packages = [ catallaxy.packages.${system}.cata ];
          shellHook = ''
            export KUBECONFIG="$HOME/.local/share/catallaxy/labs/my-platform/kube/config"
          '';
        };

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
