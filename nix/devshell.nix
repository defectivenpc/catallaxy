{
  pkgs,
  packages,
  rustToolchain,
}:

pkgs.mkShell {
  packages = packages.tools ++ [
    rustToolchain
    pkgs.bacon
    pkgs.rust-analyzer
    pkgs.mdbook
    pkgs.reveal-md

    (pkgs.writeShellScriptBin "cata-dev" ''
      exec cargo run --manifest-path "''${CATALLAXY_ROOT:-$(git rev-parse --show-toplevel)}/cli/Cargo.toml" -- "$@"
    '')
  ];

  shellHook = ''
    echo "catallaxy dev shell"
    echo "  cata-dev             # run the CLI you are editing"
    echo "  cargo build          # build CLI"
    echo "  bacon                # watch + rebuild on change"
    echo "  nix run .#cata       # the released CLI, built from a clean tree"
    echo ""
    echo "  reveal-md docs/talks/<talk>.md -w        # live-reloading slides"
    echo "  nix build .#talks                        # the decks, as published"
    echo ""
    echo "  nix build ./examples#labPackages.\"minimal.local\"  # a lab's rendered tree"
    echo "  nix run ./examples#e2e                   # stand a lab up for real"
    echo "  nix flake check                          # the gate"
  '';
}
