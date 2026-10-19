{
  lib,
  pkgs,
  floeCore,
  kubelib,

  extraFloes ? { },
}:

let
  upstreamLib = import ./upstream.nix { inherit lib pkgs kubelib; };

  builtInPaths = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ../floes));

  shadowed = lib.attrNames (lib.intersectAttrs builtInPaths extraFloes);

  allFloePaths = lib.throwIf (shadowed != [ ]) (
    "these floe names are already in the built-in set: ${lib.concatStringsSep ", " shadowed}. "
    + "A floe set is one namespace, so a lab naming one of these would get whichever "
    + "the merge happened to keep. Rename yours."
  ) (builtInPaths // extraFloes);

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

  inherit
    (catallaxy.mkLabFloeWith {
      inherit floes;
      inherit (import ./lower/cluster.nix { inherit lib catallaxy; }) placeCluster;
    })
    mkLabFloe
    ;

  labCatallaxy = catallaxy // {
    inherit mkLabFloe;
  };

  catalogue = lib.mapAttrs (_: def: map (s: s.name) (lib.attrValues def.provides)) floes;

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
  stepTypes = import ./eval/step-type.nix {
    inherit lib;
    planTokens = import ./plan-tokens.nix { inherit lib; };
  };

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
        inherit (folds) link;
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

  catallaxy = labCatallaxy;

  mkFloes = applyFloes;

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
