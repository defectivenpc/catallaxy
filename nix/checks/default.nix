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
  allocations,
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
  # allFloes :: { FloeName -> Path }, groups flattened as `lib/lab.nix` does.
  # `floe-gates.nix` takes only `.cluster` on purpose.
  allFloes = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../../floes));
in

{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  formatting = treefmtEval.config.build.check self;
}
// import ./lib-tests.nix { inherit lib pkgs floeCore; }
// import ./lab-manifests.nix { inherit lib pkgs labDefs; }
// import ./step-kinds.nix { inherit lib pkgs; }
// import ./consumer-template.nix {
  inherit lib pkgs withFloes;
  exposed = legacyPackages;
}
// import ./option-docs.nix { inherit lib pkgs optionDocs; }
// import ./generated-types.nix {
  inherit
    lib
    pkgs
    generatedTypes
    floeCrds
    ;
}
// import ./crd-coverage.nix {
  inherit
    lib
    pkgs
    labDefs
    floeCrds
    ;
}
// import ./chart-values.nix { inherit lib pkgs labDefs; }
// import ./allocations.nix { inherit lib pkgs allocations; }
// import ./teaching.nix { inherit lib pkgs; }
// import ./lib-exports.nix { inherit lib pkgs; }
// import ./signature-reach.nix {
  inherit
    lib
    pkgs
    floes
    labDefs
    ;

  # Why nothing reads these. Each is a decision; a signature that gains a
  # consumer fails this check as a stale entry, so the list cannot rot.
  unread = {
    VAULT_SERVER = "the in-cluster address, and the only would-be reader needs the other one: `lab-secret-store` is dialled from the *host*, which its own option says.";
    OCI_REGISTRY = "harbor and zot can both serve one, and nothing in the tree pushes to or pulls from an in-cluster registry yet.";
    POSTGRES_OPERATOR = "cnpg ships the capability; no floe asks for a database yet.";
    REDIS_OPERATOR = "redis-operator ships the capability; no floe asks for a cache yet.";
    CONFIG_RELOAD = "reloader will restart a workload whose ConfigMap changed; no floe asks to be restarted yet.";
    MESH_OPERATOR = "every field is link-local — a controller here, CRDs here — so neither cluster can offer it to the other and neither should.";
  };
}
// import ./prose-writes-no-options.nix { inherit lib pkgs; }
// import ./documented-outputs.nix {
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
  inherit
    lib
    pkgs
    floeCore
    labDefs
    floeCrds
    mkFloes
    ;
  floeSet = (import ../../floes).components;
  cannotKnowItsImages = [
    "custom"
  ];
}
// import ./lab-edge.nix {
  inherit
    lib
    pkgs
    mkLab
    catallaxy
    floes
    ;
}
// import ./floe-upstream.nix {
  inherit
    lib
    pkgs
    upstream
    floeCrds
    ;
  floeSet = allFloes;
}
// import ./floe-headers.nix { inherit lib pkgs; }
// import ./step-kind-producers.nix { inherit lib pkgs; }
// import ./lab-link-reads.nix { inherit lib pkgs; }
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
  inherit
    lib
    pkgs
    mkFloes
    labDefs
    ;
  catallaxy = import ../../lib/floe-catallaxy {
    inherit lib pkgs floeCore;
    crdTypes = floeCrds.types;
  };
  floeSet = allFloes;
}
// import ./floe-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/floes;
  floeSet = allFloes;
}
// import ./kind-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/kinds;
  catallaxy = import ../../lib/floe-catallaxy {
    inherit lib pkgs floeCore;
    crdTypes = floeCrds.types;
  };
}
// import ./signature-interface.nix {
  inherit lib pkgs referencePages;
  docDir = ../../docs/generated/signatures;
  catallaxy = import ../../lib/floe-catallaxy {
    inherit lib pkgs floeCore;
    crdTypes = floeCrds.types;
  };
}
// import ./content-cache.nix { inherit lib pkgs labDefs; }
// import ./cluster-documents.nix {
  inherit
    lib
    pkgs
    packages
    labDefs
    ;
}
// import ./lab-scope.nix {
  inherit
    lib
    pkgs
    mkLab
    labDefs
    catallaxy
    floes
    ;
}
// import ./secret-sharing.nix {
  inherit
    lib
    pkgs
    labDefs
    mkLab
    catallaxy
    floes
    ;
}
