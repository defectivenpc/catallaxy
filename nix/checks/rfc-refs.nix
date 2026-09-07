# Every `§N` an RFC cites resolves to a section that exists.
#
# This was written because all twenty-six `RFC 0001 §N` citations dangled at
# once. RFC 0001 shipped with unnumbered headings, and the four RFCs that
# depend on it cited sections of it anyway — including the one all four rest
# on, "§6.4 registers the category", describing a mechanism that was never
# written down anywhere. A reader chasing any of them found nothing and had
# no way to tell whether the target had moved or had never existed.
#
# Numbering RFC 0001 fixed that once. This keeps it fixed, which matters more
# for RFCs than for ordinary prose: an RFC is amended in place for years, and
# renumbering a section silently invalidates every sibling that cited it.
#
# What it checks, and only this:
#
#   `RFC 000N §X.Y`  -> RFC 000N has a section X.Y
#   `§X.Y` bare      -> the citing file has a section X.Y
#
# A "section X.Y" is either a heading numbered `X.Y`, or **item Y of the
# numbered list under heading `X`** — a convention these RFCs use throughout
# and which is worth keeping. RFC 0003's acceptance criteria are one list
# under `## 12.`, and `§12.8` naming its eighth item ("a dry run reaches no
# cloud account") is a more useful citation than a heading per criterion
# would be. Treating those as dangling would have flagged nine working
# references, so the check learns the convention rather than the other way
# round.
#
# It does not judge whether the cited section says what the citation claims.
# That is not mechanically checkable, and the `Status:` blocks are where a
# citation that has gone stale in *meaning* gets caught by a human.
{ lib, pkgs }:

let
  rfcs = builtins.attrNames (
    lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n) (builtins.readDir ../../docs/rfcs)
  );

  # `0001-floes.md` and a citation's `RFC 0001` must key the same. Both are
  # normalised by dropping leading zeros — without this every citation keys
  # a bucket that does not exist, and the check passes by finding nothing.
  denumber = n: lib.head (builtins.match "0*([0-9]+)" n);

  numberOf = name: denumber (lib.head (builtins.match "([0-9]+)-.*" name));

  lines = f: lib.splitString "\n" (builtins.readFile (../../docs/rfcs + "/${f}"));

  # Every reference an RFC offers: its heading numbers, plus `N.M` for the
  # M-th item of the top-level numbered list under heading `N`.
  #
  # One left fold, because an item number only means anything relative to the
  # heading above it. Sections numbered `0` are real — RFC 0002 and 0004 both
  # open with `## 0. What this category supplies` — so neither match may
  # assume a leading nonzero digit.
  sectionsIn =
    f:
    (lib.foldl'
      (
        acc: l:
        let
          heading = builtins.match "#+ ([0-9]+(\\.[0-9]+)?)\\.? .*" l;
          # A top-level list item: no leading whitespace, so a nested list
          # (which restarts at 1) cannot claim a number in the parent's space.
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

  # Citations, per line so the failure can name one. `builtins.match` anchors,
  # so a line is scanned by splitting on the marker rather than by a global
  # regex — Nix has no global match.
  citationsIn =
    f:
    let
      selfNum = numberOf f;

      # A citation wrapped across a line break — `RFC 0001\n§4.6` — is
      # common in eighty-column prose and would otherwise be read as a bare
      # `§4.6` against the citing file. Two of the five RFCs had one. So a
      # line's starting context is the previous line's trailing `RFC 000N`,
      # when that line ends there; otherwise this file. Deliberately one line
      # of carry and no more: `§N` on its own means *here*, and threading a
      # remembered RFC through a whole document would silently steal that.
      seedFor =
        prev:
        let
          m = if prev == null then null else builtins.match ".*RFC 0*([0-9]+)[ \t]*" prev;
        in
        if m == null then selfNum else lib.head m;

      scan =
        prev: line:
        let
          # "… RFC 0003 §7 and §12.8 …" -> [ "7 and " "12.8 …" ]
          tails = lib.tail (lib.splitString "§" line);
          # The RFC each `§` belongs to: the last `RFC 000N` before it, or
          # this file. Folding left over the segments carries that context.
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
              # `out` accumulates `{ rfc; section; line; }` in reading order.
              out =
                acc.out
                ++ (
                  if num == null then
                    [ ]
                  else
                    [
                      {
                        inherit rfc line;
                        section = lib.head num;
                      }
                    ]
                );
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

  # A citation into an RFC this repo does not carry is out of scope, not a
  # failure — nothing here can say whether it resolves.
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
      echo "An RFC cites a section that does not exist. Either the section was" >&2
      echo "renumbered — repoint the citation — or it was never written, in" >&2
      echo "which case say what the citing sentence relies on instead of" >&2
      echo "sending the reader after nothing." >&2
      exit 1
    ''}
    echo "${toString (lib.length all)} citations across ${toString (lib.length rfcs)} RFCs, all resolving" > $out
  '';
}
