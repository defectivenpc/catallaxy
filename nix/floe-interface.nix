# What a floe's interface is, written out.
#
# RFC 0001 §260-262 says the complete interface of a floe — inputs, requires,
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
}:

let
  inherit (catallaxy) floe sigs kinds;

  defOf =
    name:
    import floeSet.${name} {
      inherit lib pkgs;
      inherit
        floe
        sigs
        kinds
        ;
    };

  # ---- the lab that renders every floe ------------------------------------
  #
  # `every-floe` exists so that no floe's declarations go unchecked
  # (`floe-gates.nix`), which makes it exactly the lab to read an emitted
  # interface out of. A floe absent from it gets a declaration section and an
  # honest note instead of a fabricated one.
  renderingLab = labDefs."every-floe".config.lab;

  # `<floe name> -> { cluster; unit; }`. A lab names *units*, and a unit may be
  # called anything; `def.name` is what floe it actually is.
  placement = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        clusterName: cluster:
        lib.mapAttrsToList (
          unit: inst:
          lib.nameValuePair inst.def.name {
            inherit unit;
            cluster = clusterName;
          }
        ) cluster.floes
      ) renderingLab.clusters
    )
  );

  # ---- markdown ------------------------------------------------------------

  esc = s: lib.replaceStrings [ "|" "\n" ] [ "\\|" " " ] (toString s);

  table =
    headers: rows:
    if rows == [ ] then
      [ ]
    else
      [
        "| ${lib.concatStringsSep " | " headers} |"
        "|${lib.concatMapStrings (_: " --- |") headers}"
      ]
      ++ map (r: "| ${lib.concatMapStringsSep " | " esc r} |") rows;

  section =
    title: body:
    if body == [ ] then
      [ ]
    else
      [
        "## ${title}"
        ""
      ]
      ++ body
      ++ [ "" ];

  # A signature, as a hole sees it. The description is the signature's own, so
  # every floe requiring `X509_ISSUANCE` says the same thing about it and none
  # of them had to write it down.
  holeRows =
    holes:
    lib.mapAttrsToList (hole: sig: [
      hole
      sig.name
      sig.description
    ]) holes;

  # ---- declaration ---------------------------------------------------------

  declaration =
    name: def:
    section "Inputs" (
      table [ "input" "type" "default" "description" ] (
        lib.mapAttrsToList (n: d: [
          n
          d.type
          (if d.default == null then "*(required)*" else "`${d.default}`")
          d.description
        ]) (floe.renderInputs def.inputs)
      )
    )
    ++ section "Requires" (table [ "hole" "signature" "what it is" ] (holeRows def.requires))
    ++ section "Requires, optionally" (
      table [ "hole" "signature" "what it is" ] (holeRows def.requiresOptional)
    )
    ++ section "Provides" (table [ "promise" "signature" "what it is" ] (holeRows def.provides))
    ++ section "Emits" (
      table [ "alias" "kind" "what it carries" ] (
        lib.mapAttrsToList (alias: k: [
          alias
          k.name
          k.description
        ]) def.out
      )
    );

  # ---- what it emits, once linked -----------------------------------------

  emitted =
    name:
    let
      at = placement.${name} or null;
    in
    if at == null then
      [
        "## What it emits"
        ""
        "*No lab in this tree renders this floe, so there is nothing linked to read.*"
        "*Its declaration above is the whole of what can be said without one.*"
        ""
      ]
    else
      let
        cluster = renderingLab.clusters.${at.cluster};
        out = cluster.out;
        unit = at.unit;

        # Everything the elaborator produced is keyed `<unit>/<name>`, because
        # collection is a disjoint union over units. Ours is the prefix.
        mine = lib.filterAttrs (k: _: lib.hasPrefix "${unit}/" k);
        short = k: lib.removePrefix "${unit}/" k;

        bundles = mine out.bundles;

        provided = cluster.link.provides.${unit} or { };

        # Which fields of a promise travel and which mean something only here.
        # `T.local` is per field, so a signature is usually a mix and "this
        # one crosses" is not a property of the promise as a whole.
        localFields = sig: lib.attrNames (lib.filterAttrs (_: t: catallaxy.floe.T.isLocal t) sig.fields);

        provideBlock =
          promise: sig:
          let
            locals = localFields sig;
            value = provided.${promise} or { };
          in
          [
            "### `${promise}` — ${sig.name}"
            ""
          ]
          ++ table [ "field" "value" "" ] (
            lib.mapAttrsToList (f: v: [
              f
              "`${builtins.toJSON v}`"
              (if lib.elem f locals then "link-local" else "travels")
            ]) value
          )
          ++ [ "" ];

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
      section "Bundles" (
        table [ "bundle" "waits for" "ready when" "images" ] (
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
        )
      )
      ++ section "Provides, as linked" (
        lib.concatLists (lib.mapAttrsToList provideBlock (defOf name).provides)
      )
      # The three that change something outside this floe, and are invisible
      # from any header: a plan step reorders the deploy, an ops command adds
      # a subcommand an operator types, and a per-cluster lint judges every
      # other floe's rendered output.
      ++ section "Operator commands" (table [ "command" "what it does" ] opsRows)
      ++ section "Plan steps" (
        table [ "step" "kind" "direction" ] (
          lib.mapAttrsToList (n: s: [
            n
            s.kind
            (toString (s.direction or "deploy"))
          ]) (out.steps.${unit} or { })
        )
      )
      ++ section "Lint checks" (
        table [ "check" "scope" "what it asserts" ] (
          lib.mapAttrsToList (k: c: [
            (short k)
            c.scope
            c.description
          ]) (mine out.lint)
        )
      )
      ++ section "Verify checks" (
        table [ "check" ] (map (k: [ (short k) ]) (lib.attrNames (mine out.verify)))
      );

  document =
    name:
    let
      def = defOf name;
    in
    lib.concatStringsSep "\n" (
      [
        "# ${name}"
        ""
        def.summary
        ""
        "<!-- Generated by nix/floe-interface.nix. Refresh: nix run .#refresh-floe-docs -->"
        ""
      ]
      ++ declaration name def
      ++ emitted name
    );

  one = name: pkgs.writeText "floe-${name}.md" (document name);
in
pkgs.runCommand "floe-interfaces" { } ''
  mkdir -p $out
  ${lib.concatStringsSep "\n" (map (name: "cp ${one name} $out/${name}.md") (lib.attrNames floeSet))}
''
