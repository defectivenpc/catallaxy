# The document's wave summary against the tree it summarises.
#
# `content.waves` exists so that reading the install order is free:
# `plan-manifests` prints it without building anything. That makes it a cache,
# and a cache is a second place one fact lives — so it needs a law rather than
# a comment. L5 in `docs/cluster-spec.md`.
#
# What would go wrong without it: a bundle that moved wave, a rename that
# reached the renderer and not the summary, a projection landing in a
# different place than the summary claims. Every one of those leaves both
# sides internally consistent, passes every digest (the tree is the digest),
# and is read by an operator as the order their cluster installs in.
#
# The comparison is one-directional on purpose. The summary lists every
# bundle a floe declared; the tree holds only the ones with something to
# apply, because a bundle whose whole content is a ready probe renders no
# directory. So every directory must be in the summary, at the wave the
# summary puts it in — and a bundle in the summary with no directory is not a
# fault.
{
  lib,
  pkgs,
  labDefs,
}:

let
  compare = pkgs.writeText "content-cache.py" ''
    import json, pathlib, sys

    document, tree = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    waves = json.loads(document.read_text())["content"]["waves"]

    # `lib/eval/bundle-key.nix`: a bundle's key is its name with the path
    # separator replaced, because the name is a path and the directory is not.
    def sanitize(name):
        return name.replace("/", "__")

    summary = {sanitize(b["name"]): i for i, wave in enumerate(waves) for b in wave}

    rendered = {
        d.name: int(w.name.split("-")[0])
        for w in sorted(tree.glob("*-wave"))
        for d in sorted(w.iterdir())
        if d.is_dir()
    }

    problems = []
    for name, at in sorted(rendered.items()):
        if name not in summary:
            problems.append(
                f"the tree renders '{name}' in wave {at + 1}, "
                "and the document's summary does not list it at all"
            )
        elif summary[name] != at:
            problems.append(
                f"the tree renders '{name}' in wave {at + 1}, "
                f"and the document says wave {summary[name] + 1}"
            )

    if problems:
        print("the wave summary disagrees with the tree it summarises:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "The summary is a cache of the tree, carried so that reading the\n"
            "install order needs no build. Both sides come from the same waves,\n"
            "so a disagreement means one of them is computed from something\n"
            "else now.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    print(f"{len(rendered)} rendered bundle(s) agree with the summary")
  '';

  one =
    labName: clusterName: cluster:
    let
      document = pkgs.writeText "cluster.json" (builtins.toJSON cluster.spec);
    in
    pkgs.runCommand "content-cache-${labName}-${clusterName}" {
      nativeBuildInputs = [ pkgs.python3 ];
    } "python3 ${compare} ${document} ${cluster.manifests} > $out";
in
lib.listToAttrs (
  lib.concatMap (
    labName:
    lib.mapAttrsToList (clusterName: cluster: {
      name = "content-cache-${labName}-${clusterName}";
      value = one labName clusterName cluster;
    }) labDefs.${labName}.clusters
  ) (lib.attrNames labDefs)
)
