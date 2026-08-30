# Reading image references back out of rendered manifests.
#
# The lab package ships an `images.txt` scraped from what actually rendered
# rather than from what floes declared. The two are not the same: a chart
# carries image defaults no floe wrote down, and those are exactly the ones a
# pull-through cache has to know about. `cata images` and `warm-cache` both
# read the scrape, not the declarations.
{ lib }:

let
  # Every place in a Kubernetes manifest a container image can appear.
  #
  # Not a recursive search: `.image` also names unrelated fields on plenty of
  # CRs, and a scrape that picked those up would put non-images in the file
  # every consumer treats as a list of images.
  scrapePaths = [
    ".spec.containers"
    ".spec.initContainers"
    ".spec.template.spec.containers"
    ".spec.template.spec.initContainers"
    ".spec.jobTemplate.spec.template.spec.containers"
    ".spec.jobTemplate.spec.template.spec.initContainers"
  ];
in
{
  inherit scrapePaths;

  # `select(. != null)` belongs here rather than in each caller's pipeline. A
  # container with no `image` yields null, and a caller letting that through
  # and stripping it with `grep -v '^null$'` also deletes a real image
  # legitimately named `null`.
  scrapeExpr = "(${
    lib.concatMapStringsSep ", " (p: "${p}[]?.image") scrapePaths
  }) | select(. != null)";
}
