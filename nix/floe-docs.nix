{
  lib,
  pkgs,
  floeSet,
  labDefs,
  catallaxy,
  mkFloes,
}:

let
  inherit (catallaxy) floe;

  floes = mkFloes floeSet;

  defOf = name: floes.${name};

  placementsIn =
    labName: lab:
    lib.mapAttrsToList (
      path: floeName:
      let
        parts = lib.splitString "/" path;
        nested = lib.length parts > 1;
      in
      lib.nameValuePair floeName {
        lab = labName;
        cluster = if nested then lib.head parts else null;
        unit = if nested then lib.concatStringsSep "/" (lib.tail parts) else path;
      }
    ) lab.link.floeNames;

  candidates =
    placementsIn "every-floe" labDefs."every-floe"
    ++ lib.concatLists (lib.mapAttrsToList placementsIn (removeAttrs labDefs [ "every-floe" ]));

  entryCount =
    at:
    let
      kinds = lib.filterAttrs (_: byUnit: byUnit ? ${at.unit}) labDefs.${at.lab}.link.out;
      size = v: if lib.isAttrs v then lib.length (lib.attrNames v) else 1;
    in
    if at.cluster != null then
      0
    else
      lib.foldl' (acc: byUnit: acc + size byUnit.${at.unit}) 0 (lib.attrValues kinds);

  best =
    group:
    (lib.foldl' (
      acc: c: if entryCount c.value > entryCount acc.value then c else acc
    ) (lib.head group) (lib.tail group)).value;

  placement = lib.mapAttrs (_: best) (lib.groupBy (c: c.name) candidates);

  table = columns: rows: { inherit columns rows; };

  holeRows =
    holes:
    lib.mapAttrsToList (hole: sig: [
      hole
      "[${sig.name}](../signatures/${sig.name}.md)"
      sig.description
    ]) holes;

  # ---- declaration ---------------------------------------------------------

  declaration = name: def: [
    {
      heading = "Inputs";
      table = table [ "input" "type" "default" "description" ] (
        lib.mapAttrsToList (n: d: [
          n
          d.type
          (if d.default == null then "*(required)*" else "`${d.default}`")
          d.description
        ]) (floe.renderInputs def.inputs)
      );
    }
    {
      heading = "Requires";
      table = table [ "hole" "signature" "what it is" ] (holeRows def.requires);
    }
    {
      heading = "Requires, optionally";
      table = table [ "hole" "signature" "what it is" ] (holeRows def.optional);
    }
    {
      heading = "Provides";
      table = table [ "provision" "signature" "what it is" ] (holeRows def.provides);
    }
    {
      heading = "Emits";
      table = table [ "alias" "kind" "what it carries" ] (
        lib.mapAttrsToList (alias: k: [
          alias
          k.name
          k.description
        ]) def.out
      );
    }
  ];

  # ---- what it emits, once linked -----------------------------------------

  emitted =
    name:
    let
      at = placement.${name} or null;
    in
    if at == null then
      [
        {
          heading = "What it emits";
          lead = [
            ''
              *No lab in this tree renders this floe, so there is nothing linked to read.*
              *Its declaration above is the whole of what can be said without one.*''
          ];
        }
      ]

    else if at.cluster == null then
      let
        lab = labDefs.${at.lab};
        kinds = lib.filterAttrs (_: byUnit: byUnit ? ${at.unit}) lab.link.out;
      in
      [
        {
          heading = "What it emits";
          lead = [
            ''
              Rendered by `${at.lab}` as the lab unit `${at.unit}`. A unit of the lab
              installs nothing into a cluster, and its provisions are sealed inside the
              lab's inclusion — so its declaration above is its interface.''
          ];
        }
        {
          heading = "Output kinds";
          table = table [ "kind" "entries" ] (
            lib.mapAttrsToList (
              kind: byUnit:
              let
                value = byUnit.${at.unit};
              in
              [
                kind
                (
                  if lib.isAttrs value then
                    (if value == { } then "—" else lib.concatStringsSep ", " (lib.attrNames value))
                  else
                    "one value"
                )
              ]
            ) kinds
          );
        }
      ]

    else
      let
        cluster = labDefs.${at.lab}.clusters.${at.cluster};
        out = cluster.out;
        unit = at.unit;

        mine = lib.filterAttrs (k: _: lib.hasPrefix "${unit}/" k);
        short = k: lib.removePrefix "${unit}/" k;

        bundles = mine out.bundles;

        provideBlock = promise: sig: {
          heading = "`${promise}` — [${sig.name}](../signatures/${sig.name}.md)";
          table = table [ "field" ] (lib.mapAttrsToList (f: _: [ f ]) sig.fields);
        };

        opsRows = lib.concatLists (
          lib.mapAttrsToList (
            category: cmds:
            lib.mapAttrsToList (cmdName: c: [
              "`<lab>-ops ${category} ${cmdName}`"
              c.description
            ]) (lib.filterAttrs (n: _: lib.hasPrefix "${unit}-" n || n == unit) cmds)
          ) out.ops
        );
      in
      [
        {
          heading = "Bundles";
          table = table [ "bundle" "waits for" "ready when" "images" ] (
            lib.mapAttrsToList (
              k: b:
              let
                probe = if b.ready == null then "—" else b.ready.kind;
              in
              [
                (short k)
                (if b.needs == [ ] then "—" else lib.concatMapStringsSep ", " short b.needs)
                probe
                (if b.images == { } then "—" else lib.concatStringsSep ", " (lib.attrNames b.images))
              ]
            ) bundles
          );
        }
        {
          heading = "Provides, as linked";
          blocks = lib.mapAttrsToList provideBlock (defOf name).provides;
        }

        {
          heading = "Operator commands";
          table = table [ "command" "what it does" ] opsRows;
        }
        {
          heading = "Plan steps";
          table = table [ "step" "kind" "direction" ] (
            lib.mapAttrsToList (n: s: [
              n
              s.kind
              (toString (s.direction or "deploy"))
            ]) (out.steps.${unit} or { })
          );
        }
        {
          heading = "Lint checks";
          table = table [ "check" "scope" "what it asserts" ] (
            lib.mapAttrsToList (k: c: [
              (short k)
              c.scope
              c.description
            ]) (mine out.lint)
          );
        }
        {
          heading = "Verify checks";
          table = table [ "check" ] (map (k: [ (short k) ]) (lib.attrNames (mine out.verify)));
        }
      ];

  document =
    name:
    let
      def = defOf name;
    in
    {
      path = "floes/${name}.md";
      title = name;

      lead = [
        def.summary
        "<!-- Generated by nix/floe-docs.nix from nix build .#referencePages -->"
      ];

      sections = declaration name def ++ emitted name;
    };

  pages = map document (lib.attrNames floeSet);
in
pkgs.runCommand "floe-pages" { } ''
  mkdir -p $out
  ${lib.concatStringsSep "\n" (
    lib.imap0 (
      i: p: "cp ${pkgs.writeText "page-${toString i}.json" (builtins.toJSON p)} $out/${toString i}.json"
    ) pages
  )}
''
