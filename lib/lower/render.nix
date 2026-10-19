{ lib, pkgs }:

let
  render = import ../render/manifest.nix { inherit lib pkgs; };
  yamlUtil = import ../render/yaml.nix { inherit lib pkgs; };
  inherit (import ../eval/bundle-key.nix { }) sanitize;

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

  materialise =
    path:
    pkgs.runCommand (baseNameOf path) { } ''
      cp ${path} $out
    '';

  pad = i: lib.fixedWidthString 2 "0" (toString i);

  waitLib = import ../kubernetes/wait.nix { inherit lib; };

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
  renderCluster =
    {
      name,
      cluster,
      owner ? name,
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

      waveMeta.waves = lib.imap0 (i: wave: {
        index = i;
        bundles = map (entry: {
          key = if isProjection entry.name then entry.name else sanitize entry.name;
          dir = "${pad i}-wave/${sanitize entry.name}";
          hasContent = hasContent entry.name;
          readyProbe = normalizeProbe entry.name (entry.readyProbe or null);
          requires = entry.requires or [ ];
          provides = entry.provides or [ ];
        }) wave;
      }) cluster.waves;

      declaredBundles = lib.concatMap (w: map (e: sanitize e.name) w) cluster.waves;

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
