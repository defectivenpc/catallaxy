# What a floe's interface is, written out.
#
# The complete interface of a floe — inputs, requires,
# provides, out kinds — is available from its declaration header without
# evaluating the body. That was half true. The declaration side is there to be
# read; the *return* side is one token, `out.component = kinds.component`,
# standing for twenty-six channels. A reader could not see which bundles
# install, which `<lab>-ops` commands appear, whether the floe adds a plan step,
# or whether it lints every other floe's output.
#
# So the interface is derived rather than declared. Bundle names already live
# in `needs`, in `backs` and in the committed cli-configs; a fourth declaration
# would be churn on every rename. And the facts that matter most do not exist
# until elaboration — an ops command's name folds in the bundle it sits on
# (`elaborate.nix:322-331`), so no header could state it. Only the finished
# article can.
#
# Two sections per floe, and the split is the point:
#
#   - **Declaration** comes from the floe definition alone. True wherever the
#     floe is instantiated, and available for a floe no lab uses.
#   - **What it emits** comes from linking and elaborating it in a real lab.
#     Absent for a floe no lab renders, and the document says so rather than
#     leaving a reader to wonder whether it emits nothing.
{
  lib,
  pkgs,
  floeSet,
  labDefs,
  catallaxy,
  cataCharts,
  k8sSpecs,
}:

let
  inherit (catallaxy) floe sigs kinds;

  defOf =
    name:
    import floeSet.${name} {
      inherit
        lib
        pkgs
        catallaxy
        cataCharts
        k8sSpecs
        floes
        ;
      inherit
        floe
        sigs
        kinds
        ;
    };

  # The set a floe whose units are other floes reaches them through, built the
  # same way `lib/lab.nix` builds it and lazy for the same reason.
  floes = lib.mapAttrs (
    name: _:
    let
      def = defOf name;
    in
    def // { __functor = _: def.instantiate; }
  ) floeSet;

  # ---- where each floe is rendered ----------------------------------------
  #
  # `<floe name> -> { lab; cluster; unit; }`, or absent. A lab names *units*,
  # and a unit may be called anything; the link's `floeNames` is what floe each
  # one actually is.
  #
  # Read off the link rather than off the clusters' own attrsets, because a
  # cluster is an authored floe now and its units are inside its inclusion.
  # The link flattens them to `<cluster>/<unit>`, nested as deep as the
  # assembly goes — `core/platform/cert-manager` is a floe inside an inclusion
  # inside a cluster, and its unit name is the whole of the path below the
  # cluster, which is also how the elaborator keys its bundles.
  #
  # `cluster` is null for a key with no `/`: a unit of the lab itself, which is
  # a cluster floe, a claim, or a lab-scope floe. Those render nothing into a
  # cluster and their section says what they do instead.
  #
  # Every lab, not just `every-floe`. That lab exists so no floe's
  # *declarations* go unchecked (`floe-gates.nix`), and it reads well as the
  # one source until you notice what it cannot hold: a host floe is a unit of
  # a lab and not of a cluster, and a claim is one per provisioner. So
  # thirteen pages carried "no lab in this tree renders this floe" about floes
  # every lab in the tree renders.
  #
  # `every-floe` still wins where it has an answer, so the richest rendering
  # is the one documented; the rest are taken in name order, which is stable.
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

  # How much a placement has to show: the entries across every output kind it
  # emitted. Zero for an in-cluster floe, whose section is read off the
  # elaborated cluster instead and for which `every-floe` is already the
  # richest answer.
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

  # A floe several labs render is documented from the one that shows the most.
  # `lab-proxy` read from the first lab in name order is read from `cloud`,
  # whose ingress fronts nothing — so the page's one table came out empty
  # about the floe whose whole job is that table.
  #
  # Strict `>`, and the list is already in preference order, so a tie keeps
  # `every-floe` and then name order. A fold rather than a sort because
  # `builtins.sort` is not promised to be stable and this decides the bytes of
  # a diff-checked file.
  best =
    group:
    (lib.foldl' (
      acc: c: if entryCount c.value > entryCount acc.value then c else acc
    ) (lib.head group) (lib.tail group)).value;

  placement = lib.mapAttrs (_: best) (lib.groupBy (c: c.name) candidates);

  # ---- the page, as data ---------------------------------------------------
  #
  # What the page *is*. The markdown is `cli/src/docs/page.rs`, so this file
  # never decides how a table escapes a `|` or what an empty section looks
  # like — three generators used to answer those three ways, and a `section`
  # helper here left a stray blank line before every heading that followed a
  # `###` block.

  table = columns: rows: { inherit columns rows; };

  # A signature, as a hole sees it, linked to its own page. The description is
  # the signature's own, so every floe requiring `X509_ISSUANCE` says the same
  # thing about it and none of them had to write it down.
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
