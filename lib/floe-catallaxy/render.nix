# Lays an elaborated cluster out as numbered wave directories of YAML.
# Templating, null-stripping and ownership stamping are `lib/render/manifest.nix`'s.
{ lib, pkgs }:

let
  render = import ../render/manifest.nix { inherit lib pkgs; };
  yamlUtil = import ../render/yaml.nix { inherit lib pkgs; };
  inherit (import ../eval/bundle-key.nix { }) sanitize;

  # `mkHelmChart` says only what varies; the rest is filled here.
  toHelmSpec = spec: {
    inherit (spec)
      chart
      releaseName
      namespace
      values
      replacedHooks
      ;
    extraOpts = [ ];
    kustomize = {
      enable = false;
      resources = [ ];
      patches = [ ];
      patchesJson6902 = [ ];
    };
  };

  # A bundle carries raw YAML as a store path string, not a derivation:
  # `instantiate` deep-forces inputs and never returns from one.
  materialise =
    path:
    pkgs.runCommand (baseNameOf path) { } ''
      cp ${path} $out
    '';

  pad = i: lib.fixedWidthString 2 "0" (toString i);

  waitLib = import ../kubernetes/wait.nix { inherit lib; };

  # Probe kinds the applier runs directly. `http`, `tcp` and `dns` ask about
  # in-cluster reachability, so `wait.nix` lowers those into a one-shot Pod.
  nativeProbeKinds = [
    "condition"
    "jsonpath"
    "exists"
    "kubectl-wait"
    "script"
  ];

  normalizeProbe =
    bundleKey: probe:
    if probe == null then
      null
    else if lib.elem (probe.kind or "") nativeProbeKinds then
      probe
    else
      let
        c = waitLib.renderProbe probe;
      in
      if c ? volumeMounts then
        throw ''
          bundle '${bundleKey}' has a `ready` probe of kind '${probe.kind}'
          that needs a CA bundle mounted, which a one-shot probe Pod has no
          way to define — there is no pod spec here to add the volume to.

          Put this shape in the bundle's own workload, where the volume
          exists, and give the bundle a kubectl-native probe instead.
        ''
      else
        {
          kind = "pod";
          inherit (c) image command;
          args = c.args or [ ];
          namespace = probe.namespace or null;
          timeout = probe.timeout or null;
        };
in
{
  # renderCluster :: { name; cluster; owner ? name } -> derivation
  #
  # Wave numbering exists so the directory listing reads in apply order.
  # Nothing downstream may reference a wave index.
  renderCluster =
    {
      name,
      cluster,
      owner ? name,
      waitTimeout ? "10m",
      namespaceLabels ? { },
      namespaceResources ? [ ],
    }:
    let
      namespacesBundle = {
        resources = { };
        helmCharts = { };
        yamls =
          map (
            ns:
            builtins.toJSON {
              apiVersion = "v1";
              kind = "Namespace";
              metadata = {
                name = ns;
              }
              // lib.optionalAttrs (namespaceLabels ? ${ns}) { labels = namespaceLabels.${ns}; };
            }
          ) cluster.namespaces
          ++ map builtins.toJSON namespaceResources;
        awaitRollout = true;
      };

      # A projection renders nothing: `cata` applies it from the decrypted
      # store. It is in the graph only so a bundle can order against it.
      isProjection = lib.hasPrefix "projection/";

      emptyBundle = {
        resources = { };
        helmCharts = { };
        yamls = [ ];
        awaitRollout = true;
      };

      bundleFor =
        key:
        if key == "namespaces" then
          namespacesBundle
        else if isProjection key then
          emptyBundle
        else
          cluster.bundles.${key};

      renderOne =
        waveIndex: key:
        let
          b = bundleFor key;
        in
        {
          dir = "${pad waveIndex}-wave/${sanitize key}";
          drv = render.renderBundle key {
            ownership = {
              lab = owner;
              # Sanitized: a label value may not contain a slash.
              bundle = sanitize key;
            };
            helmCharts = lib.mapAttrs (_: toHelmSpec) (b.helmCharts or { });
            resources = b.resources or { };
            yamls = map (y: if lib.hasPrefix "/nix/store/" y then materialise y else y) (b.yamls or [ ]);
            inherit (b) awaitRollout;
          };
        };

      hasContent =
        key:
        let
          b = bundleFor key;
        in
        (b.resources or { }) != { } || (b.helmCharts or { }) != { } || (b.yamls or [ ]) != [ ];

      parts = lib.concatLists (
        lib.imap0 (
          i: wave: map (entry: renderOne i entry.name) (lib.filter (entry: hasContent entry.name) wave)
        ) cluster.waves
      );

      # The index the applier walks; its absence is a hard error.
      #
      # `key` must be sanitized to match the `catallaxy.io/bundle` label that
      # pruning compares it against. The raw form makes every resource read as
      # undeclared, and prune deletes the cluster it just built.
      waveMeta.waves = lib.imap0 (i: wave: {
        index = i;
        bundles = map (entry: {
          # Raw for a projection: the applier finds injectable Secrets by the
          # literal `projection/` prefix. Sanitizing it silently applies none.
          key = if isProjection entry.name then entry.name else sanitize entry.name;
          dir = "${pad i}-wave/${sanitize entry.name}";
          hasContent = hasContent entry.name;
          readyProbe = normalizeProbe entry.name (entry.readyProbe or null);
          requires = entry.requires or [ ];
          provides = entry.provides or [ ];
        }) wave;
      }) cluster.waves;

      # Every declared bundle, not only those with content. Sanitized to
      # match the label; anything missing here is pruned as undeclared.
      declaredBundles = lib.concatMap (w: map (e: sanitize e.name) w) cluster.waves;

      # `renderResources` writes JSON — legal YAML, but unreadable in a diff.
      assembled =
        pkgs.runCommand "floe-cluster-${name}-raw"
          {
            nativeBuildInputs = [ pkgs.yq-go ];
            waveMetaJson = builtins.toJSON waveMeta;
            passAsFile = [ "waveMetaJson" ];
          }
          ''
            mkdir -p $out
            ${lib.concatMapStringsSep "\n" (p: ''
              mkdir -p $out/${p.dir}
              cp -r ${p.drv}/. $out/${p.dir}/
            '') parts}
            chmod -R u+w $out

            cp "$waveMetaJsonPath" $out/.wave-meta

            cat > $out/.declared-bundles <<'DECLARED'
            ${lib.concatStringsSep "\n" (lib.sort (a: b: a < b) declaredBundles)}
            DECLARED

            # Only kapp reads this. Emitted anyway so flipping `cd.bootstrap`
            # later fails here rather than at apply.
            cat > $out/.deploy-config <<'EOF'
            waitTimeout: ${waitTimeout}
            EOF

            # A CRD is applyable before it is established. Scanned rather
            # than declared: a chart's CRDs are invisible to eval.
            find "$out" -mindepth 2 -maxdepth 2 -type d | while read -r bdir; do
              crds="$(
                find "$bdir" -name '*.yaml' -type f -exec \
                  yq -rN 'select(.kind == "CustomResourceDefinition")
                          | .metadata.name | select(. != null)' {} \; \
                  2>/dev/null | grep -v '^$' | sort -u || true
              )"
              if [ -n "$crds" ]; then
                printf '%s\n' "$crds" > "$bdir/.crd-wait"
              fi
            done
          '';
    in
    yamlUtil.convertDir "floe-cluster-${name}" assembled;
}
