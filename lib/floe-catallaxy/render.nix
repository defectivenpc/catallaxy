# Lays an elaborated cluster out as numbered wave directories of YAML.
#
# Deliberately thin: `lib/render/manifest.nix` already does helm templating,
# null-stripping, namespace injection and ownership stamping, and doing any of
# it again here would be a second answer to a question already answered.
{ lib, pkgs }:

let
  render = import ../render/manifest.nix { inherit lib pkgs; };
  yamlUtil = import ../render/yaml.nix { inherit lib pkgs; };
  inherit (import ../eval/bundle-key.nix { }) sanitize;

  # The bundle option type used to supply these; a floe's `mkHelmChart` says
  # only what varies, so they are filled at the boundary instead.
  toHelmSpec = spec: {
    inherit (spec)
      chart
      releaseName
      namespace
      values
      ;
    extraOpts = [ ];
    kustomize = {
      enable = false;
      resources = [ ];
      patches = [ ];
      patchesJson6902 = [ ];
    };
  };

  # A bundle carries raw YAML as a store path *string*, because `instantiate`
  # deep-forces a floe's inputs and a derivation is a self-referential attrset
  # it never comes back from. `renderYamls` branches on `isDerivation` to
  # split a CRD file per API group, so the string is turned back into one
  # here. Interpolating it keeps the string context, so the copy is a real
  # dependency and not a dangling path.
  materialise =
    path:
    pkgs.runCommand (baseNameOf path) { } ''
      cp ${path} $out
    '';

  pad = i: lib.fixedWidthString 2 "0" (toString i);

  waitLib = import ../kubernetes/wait.nix { inherit lib; };

  # The applier's probe enum (`cli/src/io/ssa/probe.rs`) knows these five and
  # `pod`. `http`, `tcp` and `dns` ask about in-cluster reachability, so they
  # cannot be run from wherever the CLI happens to be — `wait.nix` renders
  # them into a one-shot Pod instead, and that lowering happens here rather
  # than in a floe, which has no business knowing how a probe is executed.
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
  # `cluster` is an elaborated cluster from ./elaborate.nix. Waves are an
  # artifact of the topological sort, not a concept — nothing downstream may
  # reference a wave index, and the numbering exists only so the directory
  # listing reads in apply order.
  renderCluster =
    {
      name,
      cluster,
      owner ? name,
      waitTimeout ? "10m",
    }:
    let
      namespacesBundle = {
        resources = { };
        helmCharts = { };
        yamls = map (
          ns:
          builtins.toJSON {
            apiVersion = "v1";
            kind = "Namespace";
            metadata.name = ns;
          }
        ) cluster.namespaces;
        awaitRollout = true;
      };

      # A projection renders nothing at all: the Secret it stands for is
      # applied by `cata` from the decrypted store, and a value in the
      # manifest tree is exactly what must not happen. It is in the graph so a
      # bundle reading it can order against it, and `hasContent` drops it
      # before any directory is written.
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
              # Sanitized, not the raw key: a label value may not contain a
              # slash, and `<unit>/<bundle>` has one. The API server rejects
              # the whole object, not just the label.
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

      # The index the applier walks. Its absence is a hard error rather than
      # an empty apply, so it is the one file here that is not optional.
      #
      # `key` is sanitized, and that is not cosmetic. Pruning compares a
      # resource's `catallaxy.io/bundle` label against these keys and against
      # `.declared-bundles` (`cli/src/domain/prune.rs:125`). A label value may
      # not contain a slash, so the label is `gateway__controller` while the
      # elaborator's key is `gateway/controller`; writing the raw form here
      # made every applied resource read as belonging to no declared bundle,
      # and the prune pass deleted the whole cluster it had just built.
      waveMeta.waves = lib.imap0 (i: wave: {
        index = i;
        bundles = map (entry: {
          # Sanitized for everything with resources, raw for a projection.
          # The applier finds the Secrets it has to inject by looking for the
          # literal `projection/` prefix on this field
          # (`cli/src/io/ssa/mod.rs:212`), so sanitizing it here means no
          # projection is ever applied and nothing says so. A projection
          # renders no resources, so no label ever carries its name and the
          # prune comparison below is unaffected either way.
          key = if isProjection entry.name then entry.name else sanitize entry.name;
          dir = "${pad i}-wave/${sanitize entry.name}";
          hasContent = hasContent entry.name;
          readyProbe = normalizeProbe entry.name (entry.readyProbe or null);
          requires = entry.requires or [ ];
          provides = entry.provides or [ ];
        }) wave;
      }) cluster.waves;

      # Every bundle the cluster declares, not only the ones with content.
      # Sanitized for the same reason `key` is: this list is compared against
      # the `catallaxy.io/bundle` label, and a resource whose bundle is absent
      # from it is deleted as no longer declared.
      declaredBundles = lib.concatMap (w: map (e: sanitize e.name) w) cluster.waves;

      # `renderResources` writes JSON, which is legal YAML but unreadable and
      # unreviewable in a diff. The lab renderer normalises at the same point
      # for the same reason.
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

            # Read only by the kapp applier, which the kubectl-ssa path
            # returns before reaching. Emitted anyway: it is two lines, and a
            # lab that later flips `cd.bootstrap` would otherwise fail at
            # apply on a missing file rather than here.
            cat > $out/.deploy-config <<'EOF'
            waitTimeout: ${waitTimeout}
            EOF

            # A CRD is applyable before it is established, so a bundle whose
            # successors use the kind has to wait. Found by scanning rather
            # than declared, because a chart's CRDs are not visible to eval.
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
