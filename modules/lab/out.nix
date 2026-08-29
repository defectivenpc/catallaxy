# What the CLI reads: one JSON document and one store path.
#
# `cata` resolves exactly two attribute paths — `labs."<lab>"` for
# `lab.out.cliConfig` and `labPackages."<lab>"` for `lab.out.package` — and
# nothing else. Every field below is required by a Rust struct in
# `cli/src/domain/`; anything the parser defaults is omitted.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;

  clusters = config.lab.clusters;
in
{
  options.lab.out = {
    cliConfig = mkOption {
      type = types.attrs;
      internal = true;
      readOnly = true;
      description = "`LabSpec` as `cli/src/domain/lab.rs` parses it.";
    };

    package = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      description = "The rendered manifest trees, one per cluster.";
    };
  };

  config.lab.out = {
    cliConfig = {
      labName = config.lab.name;
      clusterNames = lib.attrNames clusters;
      clusters = lib.mapAttrs (_: c: c.spec) clusters;

      # Which namespaces belong to the lab, so pruning knows what it may
      # delete and what was already on the cluster.
      labNamespaces = lib.mapAttrs (_: c: c.out.namespaces) clusters;

      # Non-empty per cluster or `kube_context()` bails rather than falling
      # back to something plausible.
      runtimeContexts = lib.mapAttrs (_: c: c.spec.kubeContext) clusters;

      network = {
        name = config.lab.name;
        dockerSubnet = config.lab.network.subnet;
      };

      # `kapp` picks the `manifests/<cluster>` subdir; `kubectl-ssa` routes
      # the apply through the server-side applier that reads `.wave-meta`.
      cd = {
        strategy = "kapp";
        bootstrap = "kubectl-ssa";
        git = { };
      };

      inherit (config.lab.out) deploymentPlan teardownPlan;

      # Present because the parser requires the key, empty because none of it
      # is rebuilt yet: no host services, no pull-through registry, no
      # resolver, no secret stores.
      services = { };
      registryUpstreams = [ ];
      labOwnedRegistries = [ ];
      secrets = { };
      destroy = { };
    };

    package =
      let
        links = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: c: "ln -s ${c.manifests} $out/manifests/${name}") clusters
        );
      in
      pkgs.runCommand "lab-${config.lab.name}" { } ''
        mkdir -p $out/manifests
        ${links}

        # Under the kapp strategy the CLI reads `manifests/`, but a lab that
        # later sets a different strategy reads `bootstrap/`. One symlink
        # costs nothing and makes that switch a config change rather than a
        # renderer change.
        ln -s $out/manifests $out/bootstrap
      '';
  };
}
