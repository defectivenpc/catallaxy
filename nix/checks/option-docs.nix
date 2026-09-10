# The committed option reference matches the module tree.
#
# Same shape as the floe-interface checks and for the same reason: the pages
# are generated, so the only way they can be wrong is by being stale, and a
# stale page is worse than none — it describes an option a lab cannot set, or
# omits one it must.
{
  lib,
  pkgs,
  optionDocs,
}:

{
  # A page describing an option as "This option has no description." is a
  # page that cost more than it gave. The generator reports them; this is
  # what makes the report matter.
  option-descriptions = pkgs.runCommand "option-descriptions" { } ''
    if [ -s ${optionDocs}/undescribed.txt ]; then
      echo "option(s) with no description:" >&2
      cat ${optionDocs}/undescribed.txt >&2
      echo "" >&2
      echo "Every lab option carries one. Add a \`description\` where it is" >&2
      echo "declared rather than letting the reference say nothing." >&2
      exit 1
    fi
    touch $out
  '';

  option-docs = pkgs.runCommand "option-docs-check" { } ''
    # `undescribed.txt` is a report, not a page: `option-descriptions` is
    # what reads it.
    if ! diff -ru --exclude=undescribed.txt ${../../docs/generated} ${optionDocs} > $TMPDIR/diff; then
      cat $TMPDIR/diff >&2
      echo "" >&2
      echo "The generated option reference is stale." >&2
      echo "" >&2
      echo "These pages come from \`nixosOptionsDoc\` over the tree \`mkLab\`" >&2
      echo "evaluates, so this diff is the option surface a lab file writes" >&2
      echo "against. A default that moved without anyone meaning it is" >&2
      echo "somebody else's lab changing." >&2
      echo "" >&2
      echo "Refresh it and read the diff:" >&2
      echo "  nix run .#refresh-option-docs" >&2
      exit 1
    fi
    touch $out
  '';
}
