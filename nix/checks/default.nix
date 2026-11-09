# Checks over the RFC-0001 floe implementation.
#
# The lab system's checks went with the floe implementation they tested; these
# are what has been written back against the floe library.
{
  lib,
  pkgs,
  floeCore,
  k8sSpecs,
  self,
  packages,
  treefmtEval,
  labDefs,
  exampleLabs,
  mkLab,
  mkFloes,
  withFloes,
  optionDocs,
  cliConfigs,
  referencePages,
  generatedTypes,
  floeCrds,
  upstream,
  catallaxy,
  floes,
  legacyPackages,
  flakePackages,
}:

let
  # allFloes :: { FloeName -> Path }, groups flattened as `lib/default.nix` does.
  # `floe-gates.nix` takes only `.cluster` on purpose.
  allFloes = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../../floes));
in

{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  formatting = treefmtEval.config.build.check self;
}
// import ./lib/lib-tests.nix { inherit lib pkgs floeCore; }
// import ./labs/lab-manifests.nix { inherit lib pkgs labDefs; }
// import ./steps/step-kinds.nix { inherit lib pkgs; }
// import ./docs/consumer-template.nix {
  inherit lib pkgs withFloes;
  exposed = legacyPackages;
}
// import ./docs/option-docs.nix { inherit lib pkgs optionDocs; }
// import ./lib/schema-coverage.nix {
  inherit
    lib
    pkgs
    floeCore
    k8sSpecs
    ;
}
// import ./document/document-type.nix {
  inherit lib pkgs floeCore;
  cata = packages.cata;
  cliConfigDir = ../../examples/labs/tests/cli-configs;
}
// import ./floes/generated-types.nix {
  inherit
    lib
    pkgs
    generatedTypes
    floeCrds
    ;
}
// import ./floes/chart-values.nix { inherit lib pkgs labDefs; }
// import ./docs/teaching.nix { inherit lib pkgs; }
// import ./lib/lib-exports.nix { inherit lib pkgs; }
// import ./signatures/signature-reach.nix {
  inherit
    lib
    pkgs
    floes
    labDefs
    ;

  # Why nothing reads these. Each is a decision; a signature that gains a
  # consumer fails this check as a stale entry, so the list cannot rot.
  unread = {
    VAULT_SERVER = "the in-cluster address, and the only would-be reader needs the other one: `lab-store` is dialled from the *host*, which its own option says.";
    OCI_REGISTRY = "harbor and zot can both serve one, and nothing in the tree pushes to or pulls from an in-cluster registry yet.";
    POSTGRES_OPERATOR = "cnpg ships the capability; no floe asks for a database yet.";
    REDIS_OPERATOR = "redis-operator ships the capability; no floe asks for a cache yet.";
    CONFIG_RELOAD = "reloader will restart a workload whose ConfigMap changed; no floe asks to be restarted yet.";
    MESH_OPERATOR = "every field is link-local — a controller here, CRDs here — so neither cluster can offer it to the other and neither should.";
  };
}
// import ./docs/prose-writes-no-options.nix { inherit lib pkgs; }
// import ./docs/documented-outputs.nix {
  inherit
    lib
    pkgs
    legacyPackages
    flakePackages
    ;

  # Paths the book names that this flake does not expose, because the book is
  # describing the reader's flake there. `examples/flake.nix` is the worked
  # instance of all three.
  consumerOutputs = {
    labs = "the evaluated config `cata --flake <ref>#<lab>` resolves, which a consumer puts at this path for the CLI to find";
    labPackages = "the rendered tree beside it, and the other half of what the CLI resolves";
    labPlans = "the two plans, read back with `nix eval` when a snapshot moves";
  };
}
// import ./labs/ops-tool.nix { inherit lib pkgs; }
// import ./labs/across-labs.nix { inherit lib pkgs labDefs; }
// import ./labs/lab-checks.nix {
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
// import ./floes/floe-gates.nix {
  inherit
    lib
    pkgs
    labDefs
    mkFloes
    ;
  floeSet = (import ../../floes).components;
  cannotKnowItsImages = [
    "custom"
  ];
}
// import ./labs/lab-edge.nix {
  inherit
    lib
    pkgs
    mkLab
    catallaxy
    floes
    ;
}
// import ./floes/floe-upstream.nix {
  inherit
    lib
    pkgs
    upstream
    floeCrds
    ;
  floeSet = allFloes;
}
// import ./docs/floe-headers.nix { inherit lib pkgs; }
// import ./steps/step-kind-producers.nix { inherit lib pkgs; }
// import ./labs/lab-link-reads.nix { inherit lib pkgs; }
// import ./steps/plan-tokens.nix { inherit lib pkgs; }
// import ./docs/counts.nix {
  inherit lib pkgs;
  floeSet = allFloes;
  labDefs = exampleLabs;
}
// import ./docs/docs.nix {
  inherit lib pkgs;
  inherit (flakePackages) docs;
}
// import ./floes/floe-names.nix {
  inherit
    lib
    pkgs
    mkFloes
    labDefs
    ;
  inherit catallaxy;
  floeSet = allFloes;
}
// import ./floes/floe-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/floes;
  floeSet = allFloes;
}
// import ./kinds/kind-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/kinds;
  inherit catallaxy;
}
// import ./signatures/signature-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/signatures;
  inherit catallaxy;
}
// import ./document/content-cache.nix { inherit lib pkgs labDefs; }
// import ./document/cluster-documents.nix {
  inherit
    lib
    pkgs
    packages
    labDefs
    ;
}
// import ./labs/lab-scope.nix {
  inherit
    lib
    pkgs
    mkLab
    labDefs
    catallaxy
    floes
    ;
}
// import ./labs/secret-sharing.nix {
  inherit
    lib
    pkgs
    labDefs
    mkLab
    catallaxy
    floes
    ;
}
