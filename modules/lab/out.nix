# What the CLI reads: one JSON document and one store path.
#
# `cata` resolves exactly two attribute paths — `labs."<lab>"` for
# `lab.out.cliConfig` and `labPackages."<lab>"` for `lab.out.package` — and
# nothing else. Every field below is required by a Rust struct in
# `cli/src/domain/`; anything the parser defaults is omitted.
#
# The package is the second half of that contract and is easy to under-read:
# `cata lab lint` and `cata images` do not fail gracefully when an entry is
# absent, they abort. `metadata.json` and `images.txt` are load-bearing.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkOption types;

  clusters = config.lab.clusters;

  imageUtil = import ../../lib/render/images.nix { inherit lib; };
  chainsaw = import ../../lib/render/chainsaw.nix { inherit lib pkgs; };
  lintRender = import ../../lib/render/lint.nix { inherit lib pkgs; };
  opsRender = import ../../lib/render/ops.nix { inherit lib pkgs; };

  inherit (lintRender) sanitize;

  # ---- the operator surface, lifted off the clusters ----------------------
  #
  # The elaborator already qualified every key by the floe that wrote it, so
  # what is left is joining the clusters. Ops are the only channel that has to
  # merge rather than stay keyed by cluster, because the invocation
  # `<lab>-ops <category> <name>` has no room for a cluster.

  opsByCluster = lib.mapAttrs (_: c: c.out.ops) clusters;

  opsCategories = lib.zipAttrsWith (_category: perCluster: perCluster) (lib.attrValues opsByCluster);

  # Two clusters contributing the same `<category> <name>` is refused rather
  # than resolved: whichever won would be arbitrary, and the operator would
  # have no way to ask for the other one.
  opsCollisions = lib.concatLists (
    lib.mapAttrsToList (
      category: perCluster:
      let
        counts = lib.zipAttrsWith (_: values: lib.length values) perCluster;
      in
      lib.mapAttrsToList (
        name: n: "ops command '${category} ${name}' is declared by ${toString n} clusters"
      ) (lib.filterAttrs (_: n: n > 1) counts)
    ) opsCategories
  );

  ops = lib.mapAttrs (_category: perCluster: lib.foldl' lib.mergeAttrs { } perCluster) opsCategories;

  opsTool = opsRender.mkOpsTool {
    labName = config.lab.name;
    inherit ops;
  };

  verifyTests = lib.mapAttrs (
    name: c:
    chainsaw.mkVerifyTest {
      labName = config.lab.name;
      clusterName = name;
      checks = c.out.verify;
    }
  ) clusters;

  lintChecks = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs (
      name: c:
      lintRender.mkLintChecks {
        clusterName = name;
        checks = c.out.lint;
      }
    ) clusters
  );

  # ---- metadata.json ------------------------------------------------------
  #
  # `LabMetadata` in `cli/src/lint/mod.rs:16`. Every field it does not default
  # is required; the ones with no source in this tree yet are emitted empty,
  # which is what makes the rules that read them return nothing rather than
  # fail. `prefix` and `networkPolicies` are the two of those.

  metadata = {
    name = config.lab.name;
    prefix = "";
    clusterNames = lib.attrNames clusters;
    labNamespaces = lib.mapAttrs (_: c: c.out.namespaces) clusters;

    images = {
      requireDigest = false;
      allowedRegistries = [ ];
    };

    assertions = config.lab.assertions;
    warnings = config.lab.warnings;

    inherit (config.lab.out) deploymentPlan;

    clusters = lib.mapAttrs (_: c: {
      # Keyed by the sanitized name, because the key is matched against a
      # *file name* under `lint/<cluster>/` and a lifted channel key holds
      # slashes. The two sanitize through one function for that reason.
      lint.checks = lib.mapAttrs' (
        key: check:
        lib.nameValuePair (sanitize key) {
          inherit (check)
            description
            severity
            scope
            format
            ;
        }
      ) c.out.lint;

      # Both feed `cli/src/lint/rules/references.rs`, whose dangling-Secret
      # check needs to know what arrives from outside the manifest stream.
      # They were hardcoded empty, so that rule had no escape hatch and the
      # CLI's only knowledge of out-of-band Secrets was a hardcoded table of
      # three producers in Rust.
      inherit (c.spec) projections;
      inherit (c.out) runtimeMaterialised;

      inherit (c) assertions warnings;

      networkPolicies = {
        enabled = false;
        floes = { };
      };
    }) clusters;
  };
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
      description = "The rendered manifest trees, and everything else the CLI reads off disk.";
    };
  };

  config.lab.assertions = map (message: {
    assertion = false;
    inherit message;
  }) opsCollisions;

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
      # Which of those a lab gets is `modules/lab/cd.nix`'s answer now, read
      # off whatever provides DELIVERY_POLICY rather than fixed here.
      inherit (config.lab.out) cd;

      inherit (config.lab.out) deploymentPlan teardownPlan;

      # `checks` stays empty: `DeclaredCheck` is parsed and never dispatched
      # (`cli/src/verify/mod.rs`), so a floe's verify checks are lowered to
      # Chainsaw under `verify/` instead, which is the path that runs them.
      verify = {
        checks = { };
        endpoints = {
          inherit (config.lab.verify.endpoints) enable acceptStatuses;
        };
      };

      opsToolPath = if opsTool == null then null else "${opsTool}/bin/${config.lab.name}-ops";

      inherit (config.lab.out) services;

      dnsInfo = config.lab.dns.out.dnsInfo;

      registryPort = if config.lab.registry.enable then config.lab.registry.port else null;

      # What `plan_warm` filters an image against. Left empty, every image
      # routes to `NoUpstream` and nothing is warmed.
      registryUpstreams = lib.optionals config.lab.registry.enable (
        map (u: u.host) config.lab.registry.upstreams
      );

      # Registries the lab publishes to itself, which warming should skip
      # rather than try to fetch. Nothing publishes images yet.
      labOwnedRegistries = [ ];

      # `SecretsSpec` in `cli/src/domain/secrets.rs`. Note `writerCommand` is
      # flat there, not the nested `writer.command` this module declares.
      secrets = {
        inherit (config.lab.secrets) envFile;

        stores = lib.mapAttrs (_: store: {
          inherit (store) backend direction;
          writerCommand = store.writer.command;
          inherit (store) vault;
        }) config.lab.secrets.stores;

        managed = lib.mapAttrs (_: sec: {
          inherit (sec) store kind;
          keys = lib.mapAttrs (_: k: { inherit (k) generator length; }) sec.keys;
        }) config.lab.secrets.managed;

        hostProjections = config.lab.secrets.out.hostProjections;
      };

      # Present because the parser requires the key, empty because rescue
      # hints are not rebuilt yet.
      destroy = { };
    };

    package =
      let
        manifestLinks = lib.mapAttrsToList (
          name: c: "ln -s ${c.manifests} $out/manifests/${name}"
        ) clusters;

        # `cp -rL` rather than a symlink: `cata lab verify` walks this looking
        # for `<cluster>/chainsaw-test.yaml`, and a cluster whose floes
        # declared nothing renders a directory with no file in it.
        verifyCopies = lib.mapAttrsToList (
          name: pkg: "cp -rL ${pkg}/${name} $out/verify/${name}"
        ) verifyTests;

        lintCopies = lib.mapAttrsToList (name: pkg: "cp -rL ${pkg}/${name} $out/lint/${name}") lintChecks;

        # Scraped from what rendered, not from what floes declared: a chart
        # carries image defaults nobody wrote down, and those are exactly the
        # ones a pull-through cache has to be told about.
        scrapes = lib.mapAttrsToList (name: c: ''
          for f in $(find -L ${c.manifests} -name '*.yaml' -type f); do
            yq -N '${imageUtil.scrapeExpr}' "$f" 2>/dev/null >> images-raw.txt || true
          done
        '') clusters;
      in
      pkgs.runCommand "lab-${config.lab.name}"
        {
          nativeBuildInputs = [
            pkgs.yq-go
            pkgs.jq
          ];
          metadataText = builtins.toJSON metadata;
          passAsFile = [ "metadataText" ];
        }
        ''
          mkdir -p $out/manifests $out/verify
          ${lib.concatStringsSep "\n" manifestLinks}

          # Under the kapp strategy the CLI reads `manifests/`, but a lab that
          # later sets a different strategy reads `bootstrap/`. One symlink
          # costs nothing and makes that switch a config change rather than a
          # renderer change.
          ln -s $out/manifests $out/bootstrap

          jq . "$metadataTextPath" > $out/metadata.json

          ${lib.optionalString (config.lab.out.rootApplication != { }) ''
            mkdir -p $out/cd
            cp ${pkgs.writeText "root-application.yaml" (builtins.toJSON config.lab.out.rootApplication)} $out/cd/root-application.yaml
          ''}

          ${lib.concatStringsSep "\n" verifyCopies}
          ${lib.optionalString (lintChecks != { }) "mkdir -p $out/lint"}
          ${lib.concatStringsSep "\n" lintCopies}

          touch images-raw.txt
          ${lib.concatStringsSep "\n" scrapes}
          sort -u images-raw.txt | grep -v '^$' > $out/images.txt || touch $out/images.txt

          ${lib.optionalString (opsTool != null) ''
            mkdir -p $out/bin
            ln -s ${opsTool}/bin/${config.lab.name}-ops $out/bin/${config.lab.name}-ops
          ''}
        '';
  };
}
