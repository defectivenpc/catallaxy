{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Point this at a checkout to try a change before it is published:
    #   nix flake lock --override-input catallaxy /path/to/catallaxy
    catallaxy.url = "github:defectivenpc/catallaxy";
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
        # The distribution, with your floes in it. `withFloes` rather than
        # `mkFloes` because your floes' CRD types have to be in the record your
        # floes are *defined against*: a custom resource whose API group is
        # missing resolves to no schema and is checked for nothing. Everything
        # below comes from `cata`, so there is one record and not two.
        #
        # `floes` holds the built-in set and yours together, under one
        # namespace — taking a built-in name is refused rather than merged.
        cata = catallaxy.legacyPackages.${system}.withFloes (import ./floes);

        # `lab.nix` is a floe definition and this instantiates it: the name is
        # what every host port and the subnet are allocated from, so a second
        # environment of the same lab is a second call with a different one.
        lab = cata.mkLab (
          (import ./lab.nix {
            inherit (cata) catallaxy floes;
            inherit (nixpkgs) lib;
          })
            {
              name = "my-platform";
            }
        );
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
          labs."my-platform" = lab.cliConfig;
          labPackages."my-platform" = lab.package;
        };

        # Rendering the lab touches every option, so an unmet `requires`, a
        # bad `exports` read, or a broken anchor fails in CI rather than at
        # `lab up`.
        checks.lab-renders = lab.package;
      }
    );
}
