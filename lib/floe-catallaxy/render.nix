# Lays an elaborated cluster out as numbered wave directories of YAML.
#
# Deliberately thin: `lib/render/manifest.nix` already does helm templating,
# null-stripping, namespace injection and ownership stamping, and doing any of
# it again here would be a second answer to a question already answered.
{ lib, pkgs }:

let
  render = import ../render/manifest.nix { inherit lib pkgs; };
  yamlUtil = import ../render/yaml.nix { inherit lib pkgs; };
  inherit (import ../render/bundle-key.nix { }) sanitize;

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

      bundleFor = key: if key == "namespaces" then namespacesBundle else cluster.bundles.${key};

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

      # `renderResources` writes JSON, which is legal YAML but unreadable and
      # unreviewable in a diff. The lab renderer normalises at the same point
      # for the same reason.
      assembled = pkgs.runCommand "floe-cluster-${name}-raw" { } ''
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (p: ''
          mkdir -p $out/${p.dir}
          cp -r ${p.drv}/. $out/${p.dir}/
        '') parts}
        chmod -R u+w $out
      '';
    in
    yamlUtil.convertDir "floe-cluster-${name}" assembled;
}
