{
  self,
  lib,
  pkgs,
  system,
  nixpkgs,
  pureLib,
  packages,
  treefmtEval,
  mkLab,
  labRefusal,
  labForce,
  mkLabChecks,
  mkFloeChecks,
  exampleLabDefs,
  fixtureLabs,
  e2eLabs,
  floeSet,
  k8sTypegenConfig,
}:

let
  schemas = import ../schemas { inherit lib pkgs k8sTypegenConfig; };
in
{
  cli = packages.cataWrapped;
  cli-clippy = packages.cata.passthru.clippy;
  docs = packages.docs;
  formatting = treefmtEval.config.build.check self;
}
// import ./assertions.nix {
  inherit
    lib
    pkgs
    mkLab
    labRefusal
    ;
}
// import ./typo-assertions.nix { inherit lib pkgs labRefusal; }
// import ./capability-conflicts.nix { inherit lib pkgs labRefusal; }
// import ./floe-collisions.nix { inherit lib pkgs labRefusal; }
// import ./floe-sets.nix { inherit lib pkgs mkLab; }
// mkFloeChecks {
  inherit mkLab;
  floes = floeSet.cluster;
  labs = exampleLabDefs // fixtureLabs;
  sourceDir = ../../floes/cluster;
  # `custom` renders whatever a lab hands it, so its images and its traffic
  # are the lab's to declare and not the floe's.
  cannotKnowItsImages = [ "custom" ];
  cannotKnowItsTraffic = [ "custom" ];
}
// import ./infra-terraform.nix {
  inherit
    lib
    pkgs
    fixtureLabs
    exampleLabDefs
    ;
}
// import ./infra-refusals.nix { inherit lib pkgs labRefusal; }
// import ./resource-types.nix {
  inherit
    lib
    pkgs
    labForce
    labRefusal
    ;
}
// import ./generated-schemas.nix { inherit lib pkgs k8sTypegenConfig; }
// import ./kubeconform.nix {
  inherit lib pkgs schemas;
  labs = exampleLabDefs // fixtureLabs;
}
// import ./ownership.nix {
  inherit lib pkgs;
  labs = exampleLabDefs // fixtureLabs;
}
// import ./cli-lints.nix { inherit pkgs self; }
// import ./lib-tests.nix { inherit lib pkgs e2eLabs; }
// import ./step-kinds.nix { inherit lib pkgs system; }
// import ./host-dns.nix { inherit lib pkgs self; }
// import ./scripts.nix { inherit pkgs self; }
// import ./platform-floe-coupling.nix { inherit pkgs self; }
// import ./image-rewrite.nix { inherit lib pkgs; }
// import ./openbao-ops.nix { inherit lib pkgs mkLab; }
// import ./image-paths.nix { inherit lib pkgs self; }
// import ./image-retarget-lab.nix { inherit lib pkgs mkLab; }
// import ./sbom.nix { inherit lib pkgs mkLab; }
// import ./network-policies.nix {
  inherit lib pkgs mkLab;
  inherit (packages) cataWrapped;
  # An example lab, rendered again with policies on. Those labs leave the
  # option off, so their own output is untouched; this is the only way to
  # analyse a lab whose floes are actually wired to one another.
  policyLab =
    (mkLab {
      modules = [
        ../../examples/labs/homelab/labs/default.nix
        {
          lab.clusters.core.cluster.security.networkPolicies.enable = true;
          lab.clusters.obs.cluster.security.networkPolicies.enable = true;
        }
      ];
    }).config.lab.out.package;
  # The same lab with one deliberate lie, so there is something the rule is
  # known to reject. A check that only ever sees a passing lab cannot tell
  # "found nothing wrong" from "never ran".
  brokenPolicyLab =
    (mkLab {
      modules = [
        ../../examples/labs/homelab/labs/default.nix
        {
          lab.clusters.core.cluster.security.networkPolicies.enable = true;
          lab.clusters.obs.cluster.security.networkPolicies.enable = true;
          lab.clusters.obs.floes.grafana.network.serves.http.port = lib.mkForce 9999;
        }
      ];
    }).config.lab.out.package;
}
// import ./docs.nix {
  inherit pkgs;
  inherit (packages) optionDocs stepKindDocs;
}
// import ./external-floes.nix {
  inherit
    lib
    pkgs
    nixpkgs
    pureLib
    mkLab
    ;
}
// import ./examples.nix {
  inherit exampleLabDefs mkLabChecks;
  inherit fixtureLabs;
}
