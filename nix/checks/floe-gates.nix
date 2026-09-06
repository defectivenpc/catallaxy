# What a floe is held to, as a function of the floe set.
#
# Two of the four parked gates are gone rather than missing. `floe-boundary`
# regexed `config.floes.<name>.<field>` — a path RFC 0001 removed, and sealing
# (`lib/floe-core/types.nix`) rebuilds a provide from its signature's field
# list, so reading another floe's internals is now unrepresentable rather than
# merely checked. `every-floe-export-has-a-default` likewise: `link.nix` throws
# when a body never defines a declared provide.
#
# These two are not superseded by anything. A floe *claims* its image set is
# exhaustive and *claims* it has thought about its network, and until now both
# claims went unread.
{
  lib,
  pkgs,
  labDefs,
  floeSet,

  # Floes that cannot answer for their own images, and say so.
  #
  # An entry here is a claim that the floe *cannot know*, not that nobody got
  # round to it. `custom` is handed arbitrary resources and an optional chart
  # by whoever instantiates it; enumerating what those pull is not something
  # it can do, and claiming completeness would put a false claim in front of
  # the one gate that checks them.
  cannotKnowItsImages ? [ ],
}:

let
  imageUtil = import ../../lib/render/images.nix { inherit lib; };

  # Only the floes that install something into a cluster.
  #
  # Both gates below are about a floe's *bundles*: images are what its
  # manifests pull and network is what its workloads talk to. A floe in the
  # other delivery camp (RFC 0003 `resources`) has neither — its provider
  # binaries come from the lab's own tool, not from a registry, and nothing it
  # declares runs in the cluster at all.
  #
  # Exempted by what it emits rather than by name, so the exemption cannot go
  # stale: a resources floe that later grows bundles rejoins the gate on its
  # own, and a name in a list would have had to be noticed and removed.
  catallaxy = import ../../lib/floe-catallaxy { inherit lib pkgs; };

  defOf =
    name:
    import floeSet.${name} {
      inherit lib pkgs;
      inherit (catallaxy) floe sigs kinds;
    };

  installsIntoACluster =
    name: lib.any (k: k.name == "catallaxy.component") (lib.attrValues (defOf name).out);

  shipped = lib.filter installsIntoACluster (lib.attrNames floeSet);

  # A lab names *units*, and a unit may be called anything. `def.name` is what
  # floe it actually is, which is what a claim about the shipped set has to be
  # keyed on.
  floeNameOf = cluster: unit: cluster.floes.${unit}.def.name;

  clustersOf = lab: lab.config.lab.clusters;

  # Every (lab, cluster, unit) whose floe says its image set is exhaustive.
  claims = lib.concatLists (
    lib.mapAttrsToList (
      labName: lab:
      lib.concatLists (
        lib.mapAttrsToList (
          clusterName: cluster:
          lib.mapAttrsToList (unit: _: {
            inherit labName clusterName unit;
            floe = floeNameOf cluster unit;
            inherit cluster lab;
          }) (lib.filterAttrs (_: complete: complete) cluster.out.imagesComplete)
        ) (clustersOf lab)
      )
    ) labDefs
  );

  declaring = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: lab:
        lib.concatLists (
          lib.mapAttrsToList (
            _: cluster:
            lib.mapAttrsToList (unit: _: floeNameOf cluster unit) (
              lib.filterAttrs (_: n: n.declared) cluster.out.network
            )
          ) (clustersOf lab)
        )
      ) labDefs
    )
  );

  claimingImages = lib.unique (map (c: c.floe) claims);

  refuse =
    name: what: findings:
    pkgs.runCommand name { } ''
      ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
      ${lib.optionalString (findings != [ ]) ''
        echo "" >&2
        echo ${lib.escapeShellArg what} >&2
        exit 1
      ''}
      touch $out
    '';

  # `docker.io/traefik` and `traefik` are one image spelled two ways. Both
  # sides drop the implicit registry before they meet.
  normalise = pkgs.writeShellScript "normalise-image-refs" ''
    sed 's|^docker\.io/||' | LC_ALL=C sort -u
  '';

  # The claim, checked against what the floe's bundles actually rendered.
  # Reported all at once: declaring an image set is done by running this and
  # adding what it names, and one name per run makes that a loop as long as
  # the list.
  completenessCheck =
    c:
    let
      # `@<digest>` when the declaration pins one, because that is what the
      # rendered ref looks like and the two are compared as strings.
      #
      # This used to drop `digest` on the floor. Every chart migrated before
      # cilium's pinned by tag alone, so the declared and rendered sides
      # happened to agree and nothing noticed — but a floe installing a
      # digest-pinning chart could not have satisfied this gate at all, no
      # matter what it declared. `imageSchema` has carried the field the whole
      # time.
      declared = lib.mapAttrsToList (
        _: img:
        "${img.registry}/${img.repository}:${if img.tag == null then "" else img.tag}"
        + lib.optionalString (img.digest != null) "@${img.digest}"
      ) (lib.filterAttrs (key: _: lib.hasPrefix "${c.unit}/" key) c.cluster.out.images);
    in
    pkgs.runCommand "images-complete-${c.labName}-${c.clusterName}-${c.unit}"
      {
        nativeBuildInputs = [
          pkgs.yq-go
          pkgs.coreutils
          pkgs.findutils
        ];
      }
      ''
        tree=${c.lab.config.lab.out.package}/manifests/${c.clusterName}

        : > $TMPDIR/found
        for dir in "$tree"/*/${c.unit}__*/; do
          [ -d "$dir" ] || continue
          while read -r f; do
            yq -N '${imageUtil.scrapeExpr}' "$f" 2>/dev/null >> $TMPDIR/found || true
          done < <(find -L "$dir" -name '*.yaml' -type f)
        done

        grep -v '^\s*$' $TMPDIR/found | ${normalise} > $TMPDIR/found.sorted || true

        cat > $TMPDIR/declared.raw <<'EOF'
        ${lib.concatStringsSep "\n" declared}
        EOF
        sed 's/^\s*//' $TMPDIR/declared.raw | grep -v '^\s*$' | ${normalise} > $TMPDIR/declared || true

        missing=$(comm -23 $TMPDIR/found.sorted $TMPDIR/declared || true)
        if [ -n "$missing" ]; then
          echo "floe '${c.floe}' on ${c.labName}/${c.clusterName} claims imagesComplete," >&2
          echo "and these are in what it rendered but not in what it declared:" >&2
          echo "$missing" | sed 's/^/  /' >&2
          echo "" >&2
          echo "An operator mirroring this lab into an airgap gets the ones it" >&2
          echo "declared and a workload that cannot pull. Add them to the bundle's" >&2
          echo "\`images\`, or drop the claim." >&2
          exit 1
        fi
        touch $out
      '';

  perClaim = lib.foldl' lib.mergeAttrs { } (
    map (c: {
      "images-complete-${c.labName}-${c.clusterName}-${c.unit}" = completenessCheck c;
    }) claims
  );
in
perClaim
// {
  every-floe-declares-its-images =
    refuse "every-floe-declares-its-images"
      "A floe nobody's lab renders is a floe whose image declarations nothing checks, and its images are still images someone downstream has to mirror. `examples/labs/tests/every-floe.nix` exists for exactly the floes no example lab uses."
      (
        map (f: "floe '${f}' never claims imagesComplete in any lab") (
          lib.subtractLists (claimingImages ++ cannotKnowItsImages) shipped
        )
      );

  every-floe-declares-its-network =
    refuse "every-floe-declares-its-network"
      "A floe says what traffic it needs, or a default-deny policy silently refuses it. A floe needing nothing beyond the namespace default still sets `network.declared`, so that it reads as reviewed rather than as overlooked."
      (
        map (f: "floe '${f}' never declares its network in any lab") (lib.subtractLists declaring shipped)
      );
}
