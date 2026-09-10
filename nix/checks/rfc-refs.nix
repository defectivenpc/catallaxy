# Every `§N` cited in docs/rfcs/ resolves to a section that exists.
#
# A section is a numbered heading, or item M of the numbered list under
# heading N (`§12.8`).
{ lib, pkgs }:

let
  # denumber :: String -> RfcNumber
  denumber = n: lib.head (builtins.match "0*([0-9]+)" n);

  # numberOf :: FileName -> RfcNumber
  numberOf = name: denumber (lib.head (builtins.match "([0-9]+)-.*" name));

  # lines :: FileName -> [String]
  lines = f: lib.splitString "\n" (builtins.readFile (../../docs/rfcs + "/${f}"));

  rfcs = builtins.attrNames (
    lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir ../../docs/rfcs)
  );

  # sectionsIn :: FileName -> [SectionRef]
  sectionsIn =
    f:
    (lib.foldl'
      (
        acc: l:
        let
          heading = builtins.match "#+ ([0-9]+(\\.[0-9]+)?)\\.? .*" l;
          item = builtins.match "([0-9]+)\\. .*" l;
        in
        if heading != null then
          {
            section = lib.head (lib.splitString "." (lib.head heading));
            found = acc.found ++ [ (lib.head heading) ];
          }
        else if item != null && acc.section != null then
          acc // { found = acc.found ++ [ "${acc.section}.${lib.head item}" ]; }
        else
          acc
      )
      {
        section = null;
        found = [ ];
      }
      (lines f)
    ).found;

  sectionsByRfc = lib.listToAttrs (
    map (f: {
      name = numberOf f;
      value = sectionsIn f;
    }) rfcs
  );

  # citationsIn :: FileName -> [{ file, rfc, section, line }]
  #
  # An RFC carries across one line break, so `RFC 0001\n§4.6` reads as one
  # citation while a bare `§N` still means this file.
  citationsIn =
    f:
    let
      selfNum = numberOf f;

      # seedFor :: Nullable String -> RfcNumber
      seedFor =
        prev:
        let
          m = if prev == null then null else builtins.match ".*RFC 0*([0-9]+)[ \t]*" prev;
        in
        if m == null then selfNum else lib.head m;

      # scan :: Nullable String -> String -> [Citation]
      scan =
        prev: line:
        let
          tails = lib.tail (lib.splitString "§" line);
          heads = lib.init (lib.splitString "§" line);

          ctxOf =
            seg:
            let
              parts = builtins.match ".*RFC 0*([0-9]+)[^0-9]*$" seg;
            in
            if parts == null then null else lib.head parts;

          step =
            acc: i:
            let
              ctx = ctxOf (lib.elemAt heads i);
              rfc = if ctx != null then ctx else acc.cur;
              num = builtins.match "([0-9]+(\\.[0-9]+)?).*" (lib.elemAt tails i);
            in
            {
              cur = rfc;
              out =
                acc.out
                ++ (lib.optional (num != null) {
                  inherit rfc line;
                  section = lib.head num;
                });
            };
        in
        (lib.foldl' step {
          cur = seedFor prev;
          out = [ ];
        } (lib.range 0 (lib.length tails - 1))).out;

      ls = lines f;
    in
    map (c: c // { file = f; }) (
      lib.concatLists (lib.imap0 (i: l: scan (if i == 0 then null else lib.elemAt ls (i - 1)) l) ls)
    );

  all = lib.concatMap citationsIn rfcs;

  broken = lib.filter (
    c: (sectionsByRfc ? ${c.rfc}) && !(lib.elem c.section sectionsByRfc.${c.rfc})
  ) all;

  report = c: "  ${c.file}: cites RFC ${c.rfc} §${c.section}, which has no such section";
in
{
  rfc-refs = pkgs.runCommand "rfc-refs-tests" { } ''
    ${lib.concatMapStringsSep "\n" (c: "echo ${lib.escapeShellArg (report c)} >&2") broken}
    ${lib.optionalString (broken != [ ]) ''
      echo "" >&2
      echo "Repoint the citation, or say what the sentence relies on instead." >&2
      exit 1
    ''}
    echo "${toString (lib.length all)} citations across ${toString (lib.length rfcs)} RFCs, all resolving" > $out
  '';
}
