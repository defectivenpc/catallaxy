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
  floeSet,
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
      floeSet
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

    dns.zone = mkOption {
      type = types.str;
      default = "${config.lab.name}.test";
      defaultText = lib.literalExpression ''"''${config.lab.name}.test"'';
      description = ''
        Domain the lab's hostnames hang off, handed to floes as their
        `baseDomain`.

        Nothing resolves it yet: the host resolver and the in-cluster CoreDNS
        that made these names reachable are not rebuilt. A route is declared
        with the name and answers to it from inside the cluster.
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

    assertions = mkOption {
      type = types.listOf assertionType;
      default = [ ];
      description = ''
        Hard config-validity checks at lab scope. A failed entry fails
        evaluation, so it blocks every command that evaluates the lab.
      '';
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
