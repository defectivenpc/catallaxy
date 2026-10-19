{
  lib,
  floeSet,
  catallaxy,
  mkFloes,
  page,
}:

let
  inherit (catallaxy) sigs;
  inherit (page)
    table
    floeLink
    banner
    emitPages
    ;

  floes = mkFloes floeSet;

  touching = page.touching floes;

  touchSection = heading: field: sigName: {
    inherit heading;
    table = table [ "floe" "as" ] (
      map (t: [
        (floeLink t.floe)
        "`${field}.${t.hole}`"
      ]) (touching field sigName)
    );
  };

  document =
    sigName: sig:
    let
      providers = touching "provides" sigName;

      isProjection = !(sig ? behaviour);
    in
    {
      path = "signatures/${sigName}.md";
      title = sigName;

      lead = [
        sig.description
        banner

        ''
          Canonically `${sig.canonicalName}`. A floe providing this must declare it
          as `provides.${sig.canonicalName}`; a hole that resolves it may be called
          anything.''
      ]

      ++ lib.optional (providers == [ ] && !isProjection) ''
        *No built-in floe provides it.* A lab's own cluster floes can — they sit
        beside the `lab.nix` that places them and are not in `floes/` — so this
        is not the same as nothing answering it.''

      ++ lib.optional isProjection ''
        A **projection**: a narrowed view of another signature, for crossing a
        boundary. Whatever provides the signature it narrows answers this, so it
        has no provider of its own.'';

      sections = [
        {
          heading = "Fields";
          table = table [ "field" "type" ] (
            lib.mapAttrsToList (f: t: [
              f
              (t.name or t.tag or "—")
            ]) sig.fields
          );
        }

        (touchSection "Provided by" "provides" sigName)
        (touchSection "Required by" "requires" sigName)
        (touchSection "Required optionally by" "optional" sigName)
        (touchSection "Collected by" "collects" sigName)
        (touchSection "Exported through" "exports" sigName)
      ];
    };

  index = {
    path = "signatures/index.md";
    title = "Signatures";

    lead = [
      ''
        What one module promises another. A floe declares the signatures it
        answers and the ones it needs; the linker resolves between them, and
        neither side names the other.''
      banner
    ];

    sections = [
      {
        heading = "Every signature";
        table = table [ "signature" "canonically" "what it is" ] (
          lib.mapAttrsToList (n: sig: [
            "[${n}](./${n}.md)"
            "`${sig.canonicalName}`"
            sig.description
          ]) sigs
        );
      }
    ];
  };

  pages = [ index ] ++ lib.mapAttrsToList document sigs;
in
emitPages "signature-pages" pages
