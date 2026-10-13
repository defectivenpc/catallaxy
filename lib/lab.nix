# Evaluating a lab, and finding the ones in `examples/labs/`.
{
  lib,
  pkgs,
  floeCore,
  cataCharts,
  k8sSpecs,
  examplesPath,
}:

let
  catallaxy = import ./floe-catallaxy { inherit lib pkgs floeCore; };

  # applyFloes :: { FloeName -> Path } -> { FloeName -> Inputs -> Floe }
  #
  # `pkgs`, `cataCharts` and `k8sSpecs` are definition-time arguments rather
  # than floe inputs: `instantiate` deep-forces inputs, so a derivation could
  # not travel that way. A floe reads them to default its own `chart`, which
  # is why a lab no longer threads one.
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
            cataCharts
            k8sSpecs
            floes
            ;
          inherit (catallaxy) floe sigs kinds;
        };
      in
      def // { __functor = _: def.instantiate; }
    ) set;

  floes = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: applyFloes) (import ../floes));

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
  inherit (import ./lower/lab.nix { inherit lib pkgs; }) lowerLab;
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
          canMirror = c: lib.any (sig: sig.name == "OCI_MIRROR") (lib.attrValues c.claim.def.optional);
          cannot = lib.attrNames (lib.filterAttrs (_: c: !(canMirror c)) clusters);
        in
        lib.optional (folds.mirrors != [ ] && cannot == lib.attrNames clusters) {
          assertion = false;
          message =
            "the lab places a pull-through cache at `lab.units.${lib.head folds.mirrors}` and no "
            + "cluster can pull through it: "
            + lib.concatMapStringsSep ", " (
              n: "'${n}' is provisioned by ${clusters.${n}.claim.def.name}"
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

  # What a lab's own files are handed, which is what a floe definition is
  # handed: a lab is a floe, so its `lab.nix` is a definition and its
  # `envs/*.nix` are instantiations of it. No `config`, because there is no
  # merge to configure.
  labFileArgs = {
    inherit
      lib
      pkgs
      cataCharts
      k8sSpecs
      floes
      ;

    catallaxy = labCatallaxy;
  };

  # The name a lab answers to has to be the name it was found under.
  # `allocations.json` is keyed by the discovered one while every host port and
  # the subnet come from the written one, so a mismatch moves a lab's whole
  # allocation without moving the row that records it.
  named =
    key: lab:
    lib.throwIf (lab.name != key) (
      "the lab discovered as '${key}' calls itself '${lab.name}'. The name is what every host "
      + "port and the subnet are allocated from, and what `cata` is invoked with, so the two "
      + "cannot differ."
    ) lab;

  isNixFile = name: kind: kind == "regular" && lib.hasSuffix ".nix" name;

  discoverLabs =
    let
      labDirs = lib.filterAttrs (
        name: kind: kind == "directory" && builtins.pathExists (examplesPath + "/${name}/lab.nix")
      ) (builtins.readDir examplesPath);

      envsOf =
        labName: _:
        let
          envDir = examplesPath + "/${labName}/envs";
          def = import (examplesPath + "/${labName}/lab.nix") labFileArgs;
        in
        lib.mapAttrs' (
          filename: _:
          lib.nameValuePair "${labName}.${lib.removeSuffix ".nix" filename}" (
            named "${labName}.${lib.removeSuffix ".nix" filename}" (
              mkLab (import (envDir + "/${filename}") (labFileArgs // { lab = def; }))
            )
          )
        ) (lib.filterAttrs isNixFile (builtins.readDir envDir));
    in
    lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList envsOf labDirs);

  # A fixture is a lab with one environment, so it is one file: the whole of it
  # is the instantiation, and there is no definition to share.
  discoverFixtures =
    let
      dir = examplesPath + "/tests";
    in
    lib.optionalAttrs (builtins.pathExists dir) (
      lib.mapAttrs' (
        filename: _:
        lib.nameValuePair (lib.removeSuffix ".nix" filename) (
          named (lib.removeSuffix ".nix" filename) (mkLab (import (dir + "/${filename}") labFileArgs))
        )
      ) (lib.filterAttrs isNixFile (builtins.readDir dir))
    );
in
{
  inherit
    mkLab
    mkLabFloe
    discoverLabs
    discoverFixtures
    floes
    ;

  # The distribution, as a lab author sees it: `mkClusterFloe`, `mkLabFloe`,
  # the signatures and the kinds. What a `lab.nix` is handed, and what anything
  # building a lab outside `examples/` has to be handed too.
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
