# Reading image references back out of rendered manifests.
{ lib }:

let
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

  scrapeExpr = "(${
    lib.concatMapStringsSep ", " (p: "${p}[]?.image") scrapePaths
  }) | select(. != null)";
}
