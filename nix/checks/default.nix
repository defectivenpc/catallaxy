# Checks over the RFC-0001 floe implementation.
#
# The lab system's checks went with the floe implementation they tested; these
# are what has been written back against `lib/floe-core`.
{
  lib,
  pkgs,
  self,
  packages,
  treefmtEval,
  labDefs,
  exampleLabs,
  mkLab,
  mkFloes,
  optionDocs,
  e2eLabs,
  cloudE2eLabs,
  cliConfigs,
  floeInterfaces,
}:

let
  # allFloes :: { FloeName -> Path }, groups flattened as `lib/lab.nix` does.
  # `floe-gates.nix` takes only `.cluster` on purpose.
  allFloes = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../../floes));
in

{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  formatting = treefmtEval.config.build.check self;
}
// import ./lib-tests.nix { inherit lib pkgs; }
// import ./lab-manifests.nix { inherit lib pkgs labDefs; }
// import ./self-contained.nix { inherit lib pkgs e2eLabs; }
// import ./cloud-e2e.nix { inherit lib pkgs cloudE2eLabs; }
// import ./step-kinds.nix { inherit lib pkgs; }
// import ./consumer-template.nix {
  inherit
    lib
    pkgs
    mkLab
    mkFloes
    ;
}
// import ./option-docs.nix { inherit lib pkgs optionDocs; }
// import ./ops-tool.nix { inherit lib pkgs; }
// import ./lab-checks.nix {
  inherit
    lib
    pkgs
    packages
    labDefs
    cliConfigs
    ;
  snapshotDir = ../../examples/labs/tests/plan-snapshots;
  digestDir = ../../examples/labs/tests/manifest-digests;
  cliConfigDir = ../../examples/labs/tests/cli-configs;
}
// import ./floe-gates.nix {
  inherit lib pkgs labDefs;
  floeSet = (import ../../floes).cluster;
  cannotKnowItsImages = [
    # Handed arbitrary resources and an optional chart by whoever
    # instantiates it. Enumerating what those pull is not something it can do.
    "custom"
  ];
}
// import ./lab-edge.nix { inherit lib pkgs mkLab; }
// import ./floe-headers.nix { inherit lib pkgs; }
// import ./rfc-refs.nix { inherit lib pkgs; }
// import ./step-kind-producers.nix { inherit lib pkgs; }
// import ./plan-tokens.nix { inherit lib pkgs; }
// import ./counts.nix {
  inherit lib pkgs;
  floeSet = allFloes;
  labDefs = exampleLabs;
}
// import ./docs.nix {
  inherit lib pkgs;
  inherit (packages) docs;
}
// import ./floe-names.nix {
  inherit lib pkgs;
  catallaxy = import ../../lib/floe-catallaxy { inherit lib pkgs; };
  floeSet = allFloes;
}
// import ./floe-interface.nix {
  inherit lib pkgs floeInterfaces;
  docDir = ../../docs/floes;
  floeSet = allFloes;
}
// import ./lab-scope.nix {
  inherit
    lib
    pkgs
    mkLab
    labDefs
    ;
}
// import ./secret-sharing.nix {
  inherit
    lib
    pkgs
    labDefs
    mkLab
    ;
}
