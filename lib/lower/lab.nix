# Lowering a lab: the one JSON document the CLI reads and the one store path.
#
# `cata` resolves exactly two attribute paths — `labs."<lab>"` for the document
# and `labPackages."<lab>"` for the package — and nothing else. Every field
# below is required by a Rust struct in `cli/src/domain/`; anything the parser
# defaults is omitted.
#
# The package is the second half of that contract and is easy to under-read:
# `cata lab lint` and `cata images` do not fail gracefully when an entry is
# absent, they abort. `metadata.json` and `images.txt` are load-bearing.
#
# A plain function, and its argument list is worth reading as one: it is the
# whole of what lowering a lab needs to know, which is to say everything a lab
# holds reaches `cata` through one of these fifteen things.
{ lib, pkgs }:

{
  # lowerLab :: { … } -> { cliConfig; package; opsCollisions; }
  #
  # `opsCollisions` comes back rather than being raised here, because it is a
  # lab assertion and gathering those is the lab's job.
  #
  # `labName` rather than `name`, because three `mapAttrs (name: …)` below
  # shadow it — and did, when this was a module reading `config.lab.name`: the
  # chainsaw test came out keyed by the cluster instead of the lab, which the
  # digests caught and nothing else would have.
  lowerLab =
    {
      labName,
      clusters,
      link,
      cdArrangement,
      services,
      deploymentPlan,
      teardownPlan,
      secrets,
      verify,
      network,
      images,
      assertions,
      warnings,
    }:
    let
      dnsInfo =
        let
          emitted = lib.attrValues (link.out."catallaxy.dnsInfo" or { });
        in
        if emitted == [ ] then null else lib.head emitted;

      registrySetup = lib.findFirst (step: step.kind == "registry-setup") null deploymentPlan;

      routedHosts = lib.foldl' lib.mergeAttrs { } (
        lib.attrValues (link.out."catallaxy.routedHosts" or { })
      );

      imageUtil = import ../../lib/eval/images.nix { inherit lib; };
      infraLib = import ../../lib/render/infra.nix { inherit lib; };
      tofuProviders = import ../../lib/tofu-providers.nix { inherit lib pkgs; };

      allStacks = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: c: c.stacks) clusters);

      usedProviders = lib.unique (
        lib.concatLists (
          lib.mapAttrsToList (_: stack: lib.mapAttrsToList (_: r: r.provider) stack.resources) allStacks
        )
      );

      infraTool = tofuProviders.toolFor usedProviders;
      chainsaw = import ../../lib/render/chainsaw.nix { inherit lib pkgs; };
      lintRender = import ../../lib/render/lint.nix { inherit lib pkgs; };
      opsRender = import ../../lib/render/ops.nix { inherit lib pkgs; };

      inherit (lintRender) sanitize;

      opsByCluster = lib.mapAttrs (
        clusterName: c:
        lib.mapAttrs (
          _category: cmds: lib.mapAttrs' (n: v: lib.nameValuePair "${clusterName}-${n}" v) cmds
        ) c.out.ops
      ) clusters;

      opsCategories = lib.zipAttrsWith (_category: perCluster: perCluster) (lib.attrValues opsByCluster);

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
        labName = labName;
        inherit ops;
      };

      verifyTests = lib.mapAttrs (
        name: c:
        chainsaw.mkVerifyTest {
          labName = labName;
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

      metadata = {
        name = labName;
        prefix = "";
        clusterNames = lib.attrNames clusters;
        labNamespaces = lib.mapAttrs (_: c: c.out.namespaces) clusters;

        inherit images;

        assertions = assertions;
        warnings = warnings;

        inherit deploymentPlan;

        clusters = lib.mapAttrs (_: c: {
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

          inherit (c.spec.content) projections;
          inherit (c.out) runtimeMaterialised;

          inherit (c) assertions warnings;

          # `enabled` is whatever implements the cluster's network saying it
          # has a policy engine. `floes` stays empty: it is keyed by a floe's
          # declaration of the ports it serves, and no floe declares one — the
          # rule reading it is a check waiting on a surface that does not
          # exist, not a wiring gap.
          networkPolicies = {
            inherit (c.networkPolicy) enabled;
            floes = { };
          };
        }) clusters;
      };
    in
    {
      cliConfig = {
        labName = labName;

        infraPublications = lib.concatLists (
          lib.mapAttrsToList (
            stackName: stack:
            map (pub: {
              stack = stackName;
              outputName = infraLib.outputName pub.resource pub.output;
              inherit (pub) store key;
            }) stack.publications
          ) allStacks
        );

        clusterNames = lib.attrNames clusters;
        clusters = lib.mapAttrs (_: c: c.spec) clusters;

        inherit routedHosts;

        network = {
          name = labName;
          dockerSubnet = network.subnet;
        };

        cd = removeAttrs cdArrangement [
          "rootApplication"
          "perCluster"
        ];

        inherit deploymentPlan teardownPlan;

        verify = {
          checks = { };
          endpoints = {
            inherit (verify.endpoints) enable acceptStatuses;
          };
        };

        opsToolPath = if opsTool == null then null else "${opsTool}/bin/${labName}-ops";

        inherit services;

        # Only what `cata lab dns` points the host resolver at. The TSIG key
        # the floe also emits is for a Nix reader and stays out of a document
        # that is handed to a command — and it is a secret.
        dnsInfo = if dnsInfo == null then null else { inherit (dnsInfo) host port zone; };

        registryPort = if registrySetup == null then null else registrySetup.params.port;
        registryUpstreams = if registrySetup == null then [ ] else registrySetup.params.upstreams;

        labOwnedRegistries = [ ];

        secrets = {
          inherit (secrets) envFile;

          inherit (secrets.out) stores;

          managed = lib.mapAttrs (_: sec: removeAttrs sec [ "hostPaths" ]) secrets.out.managed;

          inherit (secrets.out) hostProjections;
        };

        destroy = { };
      };

      package =
        let
          manifestLinks = lib.mapAttrsToList (
            name: c: "ln -s ${c.manifests} $out/manifests/${name}"
          ) clusters;

          verifyCopies = lib.mapAttrsToList (
            name: pkg: "cp -rL ${pkg}/${name} $out/verify/${name}"
          ) verifyTests;

          lintCopies = lib.mapAttrsToList (name: pkg: "cp -rL ${pkg}/${name} $out/lint/${name}") lintChecks;

          scrapes = lib.mapAttrsToList (name: c: ''
            for f in $(find -L ${c.manifests} -name '*.yaml' -type f); do
              yq -N '${imageUtil.scrapeExpr}' "$f" 2>/dev/null >> images-raw.txt || true
            done
          '') clusters;

          infraRenders = lib.mapAttrsToList (stackName: stack: ''
            mkdir -p $out/infra/${stackName}
            jq . ${
              pkgs.writeText "${stackName}.tf.json" (
                builtins.toJSON (
                  infraLib.renderStack {
                    name = stackName;
                    inherit stack;
                    stacks = allStacks;
                    providers = tofuProviders.constraints;
                    stateDir = "$HOME/.local/share/catallaxy/infra/${labName}";
                  }
                )
              )
            } > $out/infra/${stackName}/main.tf.json
          '') allStacks;

          hookLinks = map (step: ''
            ln -s ${step.params.bin} $out/hooks/${step.name}
          '') (lib.filter (step: step.params.bin or null != null) (deploymentPlan ++ teardownPlan));

          autoDeployCopies = lib.concatLists (
            lib.mapAttrsToList (
              clusterName: c:
              map (m: ''
                mkdir -p $out/autodeploy/${clusterName}
                cp ${m.path} $out/autodeploy/${clusterName}/${m.name}.yaml
              '') (c.spec.provisioning.config.k3d.autoDeployManifests or [ ])
            ) clusters
          );
        in
        pkgs.runCommand "lab-${labName}"
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

            ${lib.optionalString (hookLinks != [ ]) "mkdir -p $out/hooks"}
            ${lib.concatStringsSep "\n" hookLinks}

            ${lib.concatStringsSep "\n" autoDeployCopies}

            ${lib.optionalString (allStacks != { }) ''
              mkdir -p $out/infra/bin
              ln -s ${infraTool}/bin/tofu $out/infra/bin/tofu
            ''}
            ${lib.concatStringsSep "\n" infraRenders}

            ${lib.optionalString (cdArrangement.rootApplication != { }) ''
              mkdir -p $out/cd
              cp ${pkgs.writeText "root-application.yaml" (builtins.toJSON cdArrangement.rootApplication)} $out/cd/root-application.yaml
            ''}

            ${lib.concatStringsSep "\n" verifyCopies}
            ${lib.optionalString (lintChecks != { }) "mkdir -p $out/lint"}
            ${lib.concatStringsSep "\n" lintCopies}

            touch images-raw.txt
            ${lib.concatStringsSep "\n" scrapes}
            sort -u images-raw.txt | grep -v '^$' > $out/images.txt || touch $out/images.txt

            ${lib.optionalString (opsTool != null) ''
              mkdir -p $out/bin
              ln -s ${opsTool}/bin/${labName}-ops $out/bin/${labName}-ops
            ''}
          '';

      inherit opsCollisions;
    };
}
