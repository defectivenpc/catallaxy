# Evaluating a lab.
{
  lib,
  pkgs,
  floeCore,
  kubelib,

  # Floes from outside this repository, by name. They are collected for their
  # CRD types exactly as the built-in ones are, which is the whole point: a
  # floe's custom resources are checked against a schema only if its groups
  # reached the record the floe was defined against, and that record is built
  # below. `legacyPackages.withFloes` is how a consumer gets one.
  extraFloes ? { },
}:

let
  # The CRD types the floes carry, which this hands to the distribution. It
  # cannot import them itself: a floe depends on the distribution, so the
  # distribution importing the floe tree would be the cycle.
  upstreamLib = import ./upstream.nix { inherit lib pkgs kubelib; };

  builtInPaths = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../floes));

  # A floe outside this repository cannot take a built-in name. Both halves
  # are one namespace — a link resolves `floes.<name>` against the merged set
  # — so a silent override would mean a lab linking the floe it did not mean.
  shadowed = lib.attrNames (lib.intersectAttrs builtInPaths extraFloes);

  allFloePaths = lib.throwIf (shadowed != [ ]) (
    "these floe names are already in the built-in set: ${lib.concatStringsSep ", " shadowed}. "
    + "A floe set is one namespace, so a lab naming one of these would get whichever "
    + "the merge happened to keep. Rename yours."
  ) (builtInPaths // extraFloes);

  # What this floe vendors, or null. A component floe is a directory and a lab
  # floe is a file, so only the first can carry a pin beside it.
  pinOf =
    path:
    let
      dir = if builtins.pathExists (path + "/default.nix") then path else dirOf path;
      pin = dir + "/upstream.nix";
    in
    if builtins.pathExists pin then import pin { upstream = upstreamLib; } else null;

  inherit (import ./floe-crds.nix { inherit lib; } { floeSet = allFloePaths; }) groups;

  k8sSpecs = import ./k8s-specs.nix { inherit lib pkgs; };

  catallaxy = import ./floe-catallaxy {
    inherit lib pkgs floeCore;
    k8sApi = import ./kubernetes/api.nix {
      inherit lib floeCore;
      specFile = k8sSpecs.specs."1.31";
      crdGroups = groups;
    };
  };

  # applyFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # `pkgs` and `upstream` are definition-time arguments rather than floe
  # inputs: `instantiate` deep-forces inputs, so a derivation could not travel
  # that way. `upstream` is this floe's own pin and no other's — a floe cannot
  # reach a sibling's chart, which is what a central registry allowed.
  #
  # `floes` is in that list too, and is the set being defined. A floe whose
  # units are other floes reaches them through it, and laziness is what makes
  # that legal: forcing one definition never forces the set, so a cluster floe
  # naming `floes.cert-manager` pulls one path import rather than a cycle. It
  # used to need a second pass of its own, applied after this one, because the
  # preset mechanism it needed was not a floe.
  applyFloes =
    set:
    lib.mapAttrs (
      _: path:
      let
        def = import path {
          inherit
            lib
            pkgs
            catallaxy
            floes
            ;
          upstream = pinOf path;
          inherit (catallaxy) floe sigs kinds;
        };
      in
      def // { __functor = _: def.instantiate; }
    ) set;

  floes = applyFloes allFloePaths;

  # `mkLabFloe`, finished: the helper needs the floe set above and the placer,
  # and `lib/floe-catallaxy` can see neither — the set is built out of its own
  # definitions, and `lib/lower/cluster.nix` takes the whole distribution.
  inherit
    (catallaxy.mkLabFloeWith {
      inherit floes;
      inherit (import ./lower/cluster.nix { inherit lib catallaxy; }) placeCluster;
    })
    mkLabFloe
    ;

  # The distribution a *lab* is handed, which is the one above plus the two
  # things that could only be finished here. A lab author reaches
  # `catallaxy.mkLabFloe` the way a cluster author reaches
  # `catallaxy.mkClusterFloe`, and that the one is partially applied inside is
  # not their problem.
  labCatallaxy = catallaxy // {
    inherit mkLabFloe;
  };

  # catalogue :: { FloeName -> [SignatureName] }
  #
  # What each floe provides, read off its declaration — the same read
  # `nix/floe-docs.nix` makes to generate its page. Derived, so adding a floe
  # adds it here and deleting one removes it; there is no second list.
  #
  # Lazy: `link` forces this only when a hole has no provider and it has an
  # error to write.
  catalogue = lib.mapAttrs (_: def: map (s: s.name) (lib.attrValues def.provides)) floes;

  # The four phases outside the lab's floe, each a plain function.
  inherit (import ./lower/link.nix { inherit lib catallaxy; }) linkLab;
  inherit (import ./lower/cluster.nix { inherit lib catallaxy; }) lowerCluster;
  inherit
    (import ./lower/lab.nix {
      inherit lib pkgs;
      inherit (catallaxy) conformDocument;
    })
    lowerLab
    ;
  plan = import ./lower/plan.nix { inherit lib catallaxy; };
  stepTypes = import ./eval/step-type.nix { inherit lib; };

  # mkLab :: LabInstance -> Lab
  #
  # Lab is a plain record:
  #
  #   { name; zone; subnet; clusters; link; services;
  #     cliConfig; package; deploymentPlan; teardownPlan; }
  #
  #   mkLab (labs.minimal { name = "minimal.local"; })
  #
  # A lab is a floe, so the argument is one instantiated, and `mkLab` is the
  # four phases outside it: link, lower each cluster, plan, lower the lab. They
  # are outside because a body cannot read its own units' link — that is what
  # sealing means, ADR 0007 — and every one of them is a read of it.
  mkLab =
    instance:
    let
      inherit (instance.lab)
        name
        zone
        subnet
        placements
        verifyEndpoints
        secretsEnvFile
        images
        ;

      folds = linkLab {
        labName = name;
        inherit instance catalogue;
      };

      clusters = lib.mapAttrs (
        clusterName: placed:
        placed
        // lowerCluster {
          inherit clusterName placed;

          lab = {
            inherit name;
            inherit (folds) link cdArrangement hasIngress;
          };
        }
      ) placements;

      framework = plan.frameworkSteps {
        inherit clusters;
        inherit (folds) services link;
      };

      steps = stepTypes.mergeSteps [
        folds.steps
        framework.steps
      ];

      ordered = plan.orderSteps { inherit clusters steps; };

      lowered = lowerLab {
        labName = name;
        inherit clusters;
        inherit (folds) link cdArrangement services;
        inherit (ordered) deploymentPlan teardownPlan;

        network.subnet = subnet;
        verify.endpoints = verifyEndpoints;
        inherit images;

        secrets = {
          envFile = secretsEnvFile;
          out = folds.secrets;
        };

        assertions = labAssertions;
        inherit (ordered) warnings;
      };

      storeNames = lib.mapAttrsToList (storeName: _: {
        assertion = !(lib.hasInfix "." storeName) && !(lib.hasInfix "/" storeName);
        message =
          "the secret store floe is placed at `lab.units.${storeName}`, and a store name may not "
          + "contain '.' or '/'. The CLI reads an argument containing either as a path to a file, "
          + "so this store could never be named on the command line.";
      }) folds.secrets.stores;

      unreachableMirror =
        let
          canMirror = c: lib.any (sig: sig.name == "OCI_MIRROR") (lib.attrValues c.provisioner.def.optional);
          cannot = lib.attrNames (lib.filterAttrs (_: c: !(canMirror c)) clusters);
        in
        lib.optional (folds.mirrors != [ ] && cannot == lib.attrNames clusters) {
          assertion = false;
          message =
            "the lab places a pull-through cache at `lab.units.${lib.head folds.mirrors}` and no "
            + "cluster can pull through it: "
            + lib.concatMapStringsSep ", " (
              n: "'${n}' is provisioned by ${clusters.${n}.provisioner.def.name}"
            ) cannot
            + ", which declares no OCI_MIRROR hole because it cannot mount a containerd config. "
            + "The cache would run, answer, and be consulted by nothing. Leave the floe out.";
        };

      opsCollisions = map (message: {
        assertion = false;
        inherit message;
      }) lowered.opsCollisions;

      labAssertions =
        ordered.assertions ++ framework.assertions ++ storeNames ++ unreachableMirror ++ opsCollisions;

      failed = builtins.filter (a: !a.assertion) (
        labAssertions
        ++ lib.concatLists (
          lib.mapAttrsToList (
            clusterName: cluster:
            map (entry: {
              inherit (entry) assertion;
              message = "cluster '${clusterName}': ${entry.message}";
            }) cluster.assertions
          ) clusters
        )
      );
    in
    lib.throwIf (failed != [ ])
      ("Failed assertions:\n" + lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed)
      {
        inherit
          name
          zone
          subnet
          clusters
          ;

        inherit (folds) link services;
        inherit (ordered) deploymentPlan teardownPlan;
        inherit (lowered) cliConfig package;
      };

in
{
  inherit
    mkLab
    mkLabFloe
    floes
    ;

  # The distribution, as a lab author sees it: `mkClusterFloe`, `mkLabFloe`,
  # the signatures and the kinds. What a `lab.nix` is handed, together with
  # `floes` and `lib`, whether it lives in this repo or in yours.
  catallaxy = labCatallaxy;

  # mkFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # What a consumer calls on its own floe directory. The built-in set is
  # built by the same function, so a floe outside this repo is handed the
  # same arguments as one inside it.
  mkFloes = applyFloes;

  # One cluster, with no lab around it. The same option surface a lab writes
  # under `lab.clusters.<name>`, evaluated on its own — which is possible
  # because a cluster is a floe and lowering is defined on closed
  # compositions.
  inherit
    (import ./cluster.nix {
      inherit
        lib
        catallaxy
        floes
        catalogue
        ;
    })
    mkCluster
    ;
}
