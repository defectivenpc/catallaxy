{
  lib,
  catallaxy,
  floeSet,
  mkFloes,
  page,
}:

let
  inherit (catallaxy) kinds;
  inherit (page)
    table
    floeLink
    banner
    emitPages
    ;

  floes = mkFloes floeSet;

  isKind = v: (v.__floeSig or false) && lib.hasPrefix "catallaxy." (v.name or "");
  kindSet = lib.filterAttrs (_: isKind) kinds;

  isNamed = ty: (ty.tag or null) == "record" && !lib.hasPrefix "record {" (ty.name or "record {");

  render =
    ty:
    let
      tag = ty.tag or "?";
    in
    if isNamed ty then
      "[`${ty.name}`](#${lib.toLower ty.name})"
    else if tag == "attrsOf" then
      "map of ${render ty.inner}"
    else if tag == "listOf" then
      "list of ${render ty.inner}"
    else if tag == "nullOr" then
      "${render ty.inner}, or null"
    else if tag == "record" then
      "record { ${lib.concatStringsSep ", " (lib.attrNames ty.fields)} }"
    else
      "`${ty.name or tag}`";

  # Every named record reachable from a shape, so each gets one row and one
  # table rather than being inlined at each mention.
  namedIn =
    ty:
    let
      here = lib.optional (isNamed ty) ty;
      inner = if ty ? inner then namedIn ty.inner else [ ];
      fields =
        if (ty.tag or null) == "record" then lib.concatMap namedIn (lib.attrValues ty.fields) else [ ];
      variants =
        if (ty.tag or null) == "taggedUnion" then
          lib.concatMap namedIn (lib.attrValues ty.variants)
        else
          [ ];
    in
    here ++ inner ++ fields ++ variants;

  fieldRows =
    ty:
    lib.mapAttrsToList (f: t: [
      "`${f}`"
      (render t)
    ]) ty.fields;

  # Which floes write this kind, by the name they write it under. A kind is a
  # hole field like any other, so this is `touching` over `out`.
  writers = page.touching floes "out";

  document =
    attr: kind:
    let
      # The shape itself is already the `Fields` table, so it does not earn a
      # second section of its own.
      named = lib.filter (ty: ty.name != (kind.shape.name or null)) (lib.unique (namedIn kind.shape));

      shapeIsRecord = (kind.shape.tag or null) == "record";
    in
    {
      path = "kinds/${attr}.md";
      title = kind.name;

      lead = [
        kind.description
        "Written as `out.${kind.canonicalName}`. Checked against this shape where the floe is linked, by `conformValue` — a field this does not declare is refused rather than dropped."
        banner
      ];

      sections = [
        {
          heading = "Shape";
          table = table [ "is" ] [ [ (render kind.shape) ] ];
        }
      ]
      ++ lib.optional shapeIsRecord {
        heading = "Fields";
        table = table [ "field" "type" ] (fieldRows kind.shape);
      }
      ++ map (ty: {
        heading = ty.name;
        table = table [ "field" "type" ] (fieldRows ty);
      }) named
      ++ [
        {
          heading = "Written by";
          table = table [ "floe" "as" ] (
            map (w: [
              (floeLink w.floe)
              "`out.${w.hole}`"
            ]) (writers kind.name)
          );
        }
      ];
    };

  index = {
    path = "kinds/index.md";
    title = "Output kinds";

    lead = [
      ''
        What a floe emits that no other floe asks for. A signature is answered
        by one provider and read by whoever holds the hole; a kind is collected
        from everyone who writes it and read by the distribution. ADR 0008 is
        which of the two a thing should be.''
      banner
    ];

    sections = [
      {
        heading = "Every kind";
        table = table [ "kind" "as" "what it is" ] (
          lib.mapAttrsToList (attr: k: [
            "[${k.name}](./${attr}.md)"
            "`${k.canonicalName}`"
            k.description
          ]) kindSet
        );
      }
    ];
  };

  pages = [ index ] ++ lib.mapAttrsToList document kindSet;
in
emitPages "kind-pages" pages
