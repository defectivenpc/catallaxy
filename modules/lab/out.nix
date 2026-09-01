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
  # The lab's own vault, if it has exactly one.
  #
  # Exactly one or none: two vaults is not something a single `vault`
  # store can point at, and taking the first would be choosing on the
  # lab's behalf. A lab with two says which it means, per store.
  vaultServers = lib.concatLists (
    lib.mapAttrsToList (
      _: cluster:
      lib.concatLists (
        lib.mapAttrsToList (
          unit: inst:
          lib.mapAttrsToList (instName: _: cluster.link.provides.${unit}.${instName}) (
            lib.filterAttrs (_: sig: sig.name == "VAULT_SERVER") inst.def.provides
          )
        ) cluster.floes
      )
    ) clusters
  );

  vaultServer = if lib.length vaultServers == 1 then lib.head vaultServers else null;

  opsRender = import ../../lib/render/ops.nix { inherit lib pkgs; };

  inherit (lintRender) sanitize;

  # ---- the operator surface, lifted off the clusters ----------------------
  #
  # The elaborator already qualified every key by the floe that wrote it, so
  # what is left is joining the clusters. Ops are the only channel that has to
  # merge rather than stay keyed by cluster, because the invocation
  # `<lab>-ops <category> <name>` has no room for a cluster.
  #
  # So the cluster goes in the name. Every command is `<cluster>-<name>`,
  # unconditionally — the identity of an ops command is which cluster it acts
  # on as much as which floe declared it, and two clusters running the same
  # floe are two different commands against two different kubecontexts.
  #
  # Unconditionally, rather than only when two clusters collide: a name that
  # changes when a second cluster is added is a name an operator's notes and
  # scripts stop matching, and the lab that adds the cluster is not the one
  # that finds out.

  opsByCluster = lib.mapAttrs (
    clusterName: c:
    lib.mapAttrs (
      _category: cmds: lib.mapAttrs' (n: v: lib.nameValuePair "${clusterName}-${n}" v) cmds
    ) c.out.ops
  ) clusters;

  opsCategories = lib.zipAttrsWith (_category: perCluster: perCluster) (lib.attrValues opsByCluster);

  # A backstop now rather than the main line of defence: qualifying by cluster
  # makes the ordinary collision impossible, and what is left is a cluster
  # named so that its prefix reproduces another's — `core` with a command
  # `x-y` against a cluster `core-x` with `y`. Contrived, and silent if it
  # happened, so it stays checked.
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

          # A `vault` store's server, mount and version filled in from
          # whatever provides VAULT_SERVER, for the fields the lab left unset.
          #
          # Done here rather than as option defaults on the store itself,
          # which is where it belongs and where it cannot go: deriving them
          # needs to know *which* stores are `backend = "vault"`, and reading
          # `lab.secrets.stores` to write `lab.secrets.stores` is infinite
          # recursion. This reads the option and writes somewhere else.
          #
          # The lab still wins. openbao knows its own address and a lab that
          # names one is pointing at a vault outside itself, which is a
          # different and equally real thing.
          vault =
            if store.backend != "vault" || vaultServer == null then
              store.vault
            else
              {
                server = if store.vault.server != null then store.vault.server else vaultServer.address;
                path = if store.vault.path != "secret" then store.vault.path else vaultServer.kvPath;
                version = if store.vault.version != "v2" then store.vault.version else vaultServer.kvVersion;
              };
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

        # Auto-deploy manifests, copied into the package.
        #
        # `provisionerConfig.k3d.autoDeployManifests[].path` is a store path
        # that reaches the CLI as a plain string in `metadata.json`. Nothing in
        # this derivation's inputs referenced it — the rendered manifests do
        # not, and `builtins.toJSON` through `passAsFile` drops string context
        # — so Nix never realised it and k3d found no file to mount. Copying it
        # here makes the package depend on it by construction.
        #
        # `autodeploy/<cluster>/<name>.yaml` is the layout
        # `cli/src/provision/mod.rs` already looks in before falling back to
        # the declared path, so nothing on the CLI side changes.
        autoDeployCopies = lib.concatLists (
          lib.mapAttrsToList (
            clusterName: c:
            map (m: ''
              mkdir -p $out/autodeploy/${clusterName}
              cp ${m.path} $out/autodeploy/${clusterName}/${m.name}.yaml
            '') c.spec.provisionerConfig.k3d.autoDeployManifests
          ) clusters
        );
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

          ${lib.concatStringsSep "\n" autoDeployCopies}

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
