# The regression net over whole labs.
#
# `checks.floe-cluster` pins the merge and the derived order as *values*;
# `lab-manifests` pins that one lab reaches the ground. These pin every lab,
# file by file, and the properties that only exist between labs.
#
# Adapted rather than copied from `old-floes/lib/lab-checks.nix`: the option
# paths moved (`lab.network.dockerSubnet` → `lab.network.subnet`) and two
# families wait on features that are not back (`lab-mesh-ports` needs netbird,
# and the Talos half of the subnet check needs that provisioner).
{
  lib,
  pkgs,
  packages,
  labDefs,
  snapshotDir,
  digestDir,
}:

let
  net = import ../../lib/util/network.nix { inherit lib; };

  cata = packages.cataWrapped;

  # ---- per-lab -----------------------------------------------------------

  # Forces the manifest tree and throws it away. That proves the lab
  # evaluates and nothing about what it says, which is what the digest is for.
  evalCheck =
    name: lab:
    pkgs.runCommand "${name}-eval" { } ''
      cat > /dev/null <<'EOF'
      ${toString (lib.mapAttrsToList (_: c: c.manifests) lab.config.lab.clusters)}
      EOF
      touch $out
    '';

  # One line per file: sha256 of the file with store hashes normalised, sorted
  # by path. The normalisation is what stops a chart rebuilt from newer
  # nixpkgs reading as a change to what the lab declares — a fixture that
  # moved on every input bump would be refreshed without being read.
  #
  # This pipeline and `pkgs/refresh-digests.nix` must stay byte-identical.
  digestCheck =
    name: lab:
    pkgs.runCommand "manifest-digest-${name}"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnused
          pkgs.diffutils
        ];
      }
      ''
        cd ${lab.config.lab.out.package}
        find -L . -type f | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
          hash=$(sed 's|/nix/store/[a-z0-9]\{32\}-|/nix/store/HASH-|g' "$f" \
            | sha256sum | cut -d' ' -f1)
          printf '%s  %s\n' "$hash" "$f"
        done > $TMPDIR/actual.txt

        if ! diff -u ${digestDir}/${name}.digest.txt $TMPDIR/actual.txt; then
          echo "" >&2
          echo "What ${name} renders no longer matches the committed digest." >&2
          echo "Each line above names one file that appeared, vanished or changed." >&2
          echo "" >&2
          echo "A refactor that meant to change nothing should show no diff here." >&2
          echo "If the diff is intentional, refresh it:" >&2
          echo "" >&2
          echo "  nix run .#refresh-digests" >&2
          exit 1
        fi
        touch $out
      '';

  # A bundle key that reaches a resource without reaching `.declared-bundles`
  # is deleted on the next `lab up`: pruning compares the label against the
  # declaration. A synthetic bundle missing from the file once did exactly
  # that to a lab's own namespaces.
  #
  # The static twin of the e2e "no longer declares" assertion.
  declaredBundlesCheck =
    name: lab:
    pkgs.runCommand "${name}-declared-bundles"
      {
        nativeBuildInputs = [
          pkgs.yq-go
          pkgs.coreutils
          pkgs.findutils
        ];
      }
      ''
        tree=${lab.config.lab.out.package}/manifests
        status=0

        for dir in "$tree"/*/; do
          cluster=$(basename "$dir")
          [ -f "$dir/.declared-bundles" ] || continue

          grep -v '^\s*$' "$dir/.declared-bundles" | LC_ALL=C sort -u > "$TMPDIR/declared"

          # `..` rather than a line match: the label counts wherever it
          # appears, pod template included, and reading it off the line with
          # sed got the value wrong in every case YAML allows.
          : > "$TMPDIR/seen"
          while read -r f; do
            yq -N '.. | select(tag == "!!map" and has("catallaxy.io/bundle")) | .["catallaxy.io/bundle"]' \
              "$f" 2>/dev/null >> "$TMPDIR/seen" || true
          done < <(find -L "$dir" -name '*.yaml' -type f)

          grep -v '^\s*$' "$TMPDIR/seen" | LC_ALL=C sort -u > "$TMPDIR/seen.sorted" || true

          undeclared=$(comm -23 "$TMPDIR/seen.sorted" "$TMPDIR/declared")
          if [ -n "$undeclared" ]; then
            echo "cluster '$cluster' applies resources labelled with bundles it does not declare:" >&2
            echo "$undeclared" | sed 's/^/  /' >&2
            status=1
          fi
        done

        if [ "$status" != 0 ]; then
          echo "" >&2
          echo "'lab up' prunes anything carrying this lab's label whose bundle the" >&2
          echo "declaration no longer names, so a bundle key that reaches a resource" >&2
          echo "without reaching .declared-bundles deletes that resource on the next" >&2
          echo "run. Add it the way the synthetic 'namespaces' bundle is." >&2
          exit 1
        fi
        touch $out
      '';

  # A chart that mints its own credential while rendering puts that credential
  # in the manifest, in the digest that pins it, and in the Nix store — and it
  # changes on every re-render, so applying the lab again silently rotates it.
  secretMaterialCheck =
    name: lab:
    pkgs.runCommand "${name}-renders-no-secret-material" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      python3 ${../../lib/checks/secret-material.py} ${lab.config.lab.out.package}
      touch $out
    '';

  # The 12 lint rules, over the *rendered* tree — Helm output included.
  lintCheck =
    name: lab:
    pkgs.runCommand "${name}-lint" { nativeBuildInputs = [ cata ]; } ''
      cata lab lint --path ${lab.config.lab.out.package}
      touch $out
    '';

  planSnapshotCheck =
    name: lab: direction:
    let
      plan =
        if direction == "deploy" then
          lab.config.lab.out.deploymentPlan
        else
          lab.config.lab.out.teardownPlan;

      planJson = pkgs.writeText "${name}-${direction}-plan.json" (builtins.toJSON plan);
      expected = "${snapshotDir}/${name}.${direction}.expected.txt";
    in
    pkgs.runCommand "plan-${direction}-${name}"
      {
        nativeBuildInputs = [
          cata
          pkgs.diffutils
        ];
      }
      ''
        cata lab plan --stable --from-file ${planJson} > $TMPDIR/actual.txt

        if ! diff -u ${expected} $TMPDIR/actual.txt; then
          echo "" >&2
          echo "The ${direction} plan for ${name} changed." >&2
          echo "Step order, the step set and every param are pinned here, because" >&2
          echo "a derived plan changing is exactly what nobody notices." >&2
          echo "" >&2
          echo "If intended, refresh it:" >&2
          echo "  cata --flake . lab plan ${name} --stable ${
            lib.optionalString (direction == "teardown") "--teardown "
          }\\" >&2
          echo "    > ${builtins.toString snapshotDir}/${name}.${direction}.expected.txt" >&2
          exit 1
        fi
        touch $out
      '';

  perLab = lib.concatLists (
    lib.mapAttrsToList (name: lab: [
      { "${name}-eval" = evalCheck name lab; }
      { "manifest-digest-${name}" = digestCheck name lab; }
      { "${name}-declared-bundles" = declaredBundlesCheck name lab; }
      { "${name}-renders-no-secret-material" = secretMaterialCheck name lab; }
      { "${name}-lint" = lintCheck name lab; }
      { "plan-deploy-${name}" = planSnapshotCheck name lab "deploy"; }
      { "plan-teardown-${name}" = planSnapshotCheck name lab "teardown"; }
    ]) labDefs
  );

  # ---- between labs ------------------------------------------------------
  #
  # Everything about a lab is already named after it and cannot clash. Its
  # subnet and its host ports are the two things it has to be *given* on
  # purpose, and two labs that cannot be up at once is a fact nobody
  # discovers until the second one fails to start.

  subnetOf = lab: lab.config.lab.network.subnet;

  subnetClashes = lib.concatLists (
    lib.mapAttrsToList (
      a: labA:
      lib.concatLists (
        lib.mapAttrsToList (
          b: labB:
          lib.optional (
            a < b && net.cidrsOverlap (subnetOf labA) (subnetOf labB)
          ) "${a} (${subnetOf labA}) overlaps ${b} (${subnetOf labB})"
        ) labDefs
      )
    ) labDefs
  );

  # Each port is claimed only when the feature that binds it is on.
  portsOf =
    lab:
    let
      c = lab.config.lab;
    in
    lib.optional c.proxy.enable {
      what = "proxy.httpPort";
      port = c.proxy.httpPort;
    }
    ++ lib.optional (c.proxy.enable && c.proxy.tls.enable) {
      what = "proxy.httpsPort";
      port = c.proxy.httpsPort;
    }
    ++ lib.optional c.registry.enable {
      what = "registry.port";
      port = c.registry.port;
    }
    ++ lib.optional c.dns.enable {
      what = "dns.hostPort";
      port = c.dns.hostPort;
    }
    ++ lib.optional c.egress.enable {
      what = "egress.port";
      port = c.egress.port;
    };

  claims = lib.concatLists (
    lib.mapAttrsToList (name: lab: map (p: p // { lab = name; }) (portsOf lab)) labDefs
  );

  portClashes = lib.concatLists (
    map (
      port:
      let
        holders = lib.filter (c: c.port == port) claims;
      in
      lib.optional (lib.length holders > 1) (
        "host port ${toString port} is claimed by "
        + lib.concatMapStringsSep ", " (h: "${h.lab}'s ${h.what}") holders
      )
    ) (lib.unique (map (c: c.port) claims))
  );

  # A hostname with a public route inside a cluster and no backend on the lab
  # proxy reaches the proxy's default backend and gets a 503, with nothing
  # saying why.
  unproxiedHosts = lib.concatLists (
    lib.mapAttrsToList (
      name: lab:
      lib.optionals lab.config.lab.proxy.enable (
        let
          routed = lib.unique (
            lib.concatLists (
              lib.mapAttrsToList (
                _: c: map (h: h.host) (lib.filter (h: h.tier == "public") c.out.exposedHosts)
              ) lab.config.lab.clusters
            )
          );
        in
        map (h: "${name} routes '${h}' publicly and its proxy has no backend for it") (
          lib.subtractLists lab.config.lab.proxy.out.hosts routed
        )
      )
    ) labDefs
  );

  refuse =
    checkName: what: findings:
    pkgs.runCommand checkName { } ''
      ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
      ${lib.optionalString (findings != [ ]) ''
        echo "" >&2
        echo ${lib.escapeShellArg what} >&2
        exit 1
      ''}
      touch $out
    '';
in
lib.foldl' lib.mergeAttrs { } perLab
// {
  lab-subnets =
    refuse "lab-subnets"
      "Two labs whose docker networks overlap cannot be up at once, and the second one to start fails on an address the first already has."
      subnetClashes;

  lab-host-ports =
    refuse "lab-host-ports"
      "Two containers cannot bind one host port. Everything else about a lab is named after it and does not clash; the ports are the one thing a lab has to be given on purpose."
      portClashes;

  lab-routed-hosts-are-proxied =
    refuse "lab-routed-hosts-are-proxied"
      "A public route the proxy has no backend for reaches its default backend and returns 503. The proxy builds its host map from what the clusters expose, so a hostname named anywhere else is invisible to it."
      unproxiedHosts;
}
