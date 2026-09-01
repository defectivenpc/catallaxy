# The lab option surface.
#
# A lab is a NixOS module, not a floe. Floes are the inter-component
# interface, which the module system is bad at; a lab is partial
# configuration merged from several files, which is what it is good at.
#
# Every option here exists because a field the CLI requires cannot be derived
# without it. The surface grows when a feature needs it and not before.
{
  config,
  lib,
  pkgs,
  catallaxy,
  cataCharts,
  k8sSpecs,
  floes,
  ...
}:

let
  inherit (lib) mkOption types;

  clusterSubmodule = import ./cluster.nix {
    inherit
      lib
      pkgs
      catallaxy
      cataCharts
      k8sSpecs
      floes
      ;
    lab = config.lab;
  };

  assertionType = types.submodule {
    options = {
      assertion = mkOption {
        type = types.bool;
        description = "True = check passes. False = violation reported.";
      };
      message = mkOption {
        type = types.str;
        description = ''
          Diagnostic shown when the assertion fails. Name the option path and
          what the user should change.
        '';
      };
    };
  };
in
{
  options.lab = {
    name = mkOption {
      type = types.str;
      description = ''
        Unique name for the lab. Also the docker network name and the prefix
        on every k3d container, so two labs on one host do not collide.
      '';
    };

    network.subnet = mkOption {
      type = types.str;
      default = "172.20.0.0/16";
      description = ''
        Docker network the lab's containers share, in CIDR form. `cata lab up`
        parses this before it runs anything, to refuse a lab whose subnet
        overlaps one already on the host.
      '';
    };

    network.gateway = mkOption {
      type = types.str;
      default =
        (import ../../lib/util/network.nix { inherit lib; }).cidrFirstIP
          config.lab.network.subnet;
      defaultText = lib.literalExpression "the address after the subnet's own";
      description = "Gateway address within the subnet.";
    };

    clusters = mkOption {
      type = types.attrsOf clusterSubmodule;
      default = { };
      description = ''
        The clusters this lab builds. Each one links its floes and elaborates
        them into a cluster picture; the lab lowers that into what the CLI
        reads.
      '';
    };

    unstable = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "netbird's setup key has to be fetched by hand; see floes/cluster/netbird.";
      description = ''
        Why this lab is not expected to stand up, or null when it is.

        The migration off the parked floe set moves faster than every lab can
        be made to run, and a lab that renders but does not deploy is worth
        having in the tree: it renders, it lints, its plan is snapshotted, and
        its digest is pinned, so the ninety-odd checks that do not need a
        cluster all apply to it. What it must not do is fail in CI as though
        someone had broken it.

        A string rather than a bool, because "unstable" with no reason is a
        note to nobody. It joins `lab.out.selfContained.reasons`, so the e2e
        runner skips the lab and prints this, and `nix/checks/self-contained.nix`
        pins it — a lab going unstable, becoming stable, or quietly staying
        unstable forever is a diff in that table either way.

        This is the one declared entry among derived ones. Everything else in
        `selfContained` is read off the lab; this cannot be, because "the
        operator races on a fresh install" is not a fact any expression here
        can compute.
      '';
    };

    assertions = mkOption {
      type = types.listOf assertionType;
      default = [ ];
      description = ''
        Hard config-validity checks at lab scope. A failed entry fails
        evaluation, so it blocks every command that evaluates the lab.
      '';
    };

    warnings = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Soft advisories at lab scope, carried into `metadata.json` and
        surfaced by `cata lab lint`.

        The counterpart to `assertions`: something worth saying that is not
        worth refusing to build over. A floe's warnings arrive here already
        prefixed with the floe that raised them.
      '';
    };

    verify.endpoints = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Probe every publicly routed hostname the clusters expose.

          The hosts and the paths come from `cluster.out.exposedHosts`, which
          the elaborator reads off the rendered routes, so this needs no list
          to maintain.
        '';
      };

      acceptStatuses = mkOption {
        type = types.listOf (types.ints.between 100 599);
        default = [ ];
        example = [
          401
          403
        ];
        description = ''
          Extra HTTP statuses that count as the endpoint answering.

          A gateway that routes to a workload demanding auth answers 401, and
          that proves the route works. 404 is deliberately not listable here:
          it is what a gateway returns when it has *no* route, which is the
          failure this check exists to catch.
        '';
      };
    };
  };

  options.assertions = mkOption {
    type = types.listOf assertionType;
    default = [ ];
    internal = true;
    visible = false;
    description = ''
      Every assertion in the lab, gathered from `lab.assertions` and from each
      cluster. `lib/lab.nix` reads this one path and throws on any failure, so
      a lab that violates a constraint fails `nix eval` rather than reaching a
      cluster.
    '';
  };

  config.assertions =
    config.lab.assertions
    ++ lib.concatLists (
      lib.mapAttrsToList (
        clusterName: cluster:
        map (entry: {
          inherit (entry) assertion;
          message = "cluster '${clusterName}': ${entry.message}";
        }) cluster.assertions
      ) config.lab.clusters
    );
}
