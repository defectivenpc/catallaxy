# The regression net over whole labs.
#
# `checks.floe-cluster` pins the merge and the derived order as *values*;
# `lab-manifests` pins that one lab reaches the ground. These pin every lab,
# file by file, and the properties that only exist between labs.
#
# Adapted rather than copied from the previous `lib/lab-checks.nix`: the option
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
  cliConfigDir,
  cliConfigs,
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

  # Every lint rule, over the *rendered* tree — Helm output included.
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
          echo "If intended, refresh every snapshot and read the diff:" >&2
          echo "  nix run .#refresh-plans" >&2
          exit 1
        fi
        touch $out
      '';

  # What the CLI parses, pinned field by field.
  #
  # The digest covers what a lab *renders* and the plan snapshots cover what
  # it *does*. Neither covers what it *is*: `provisioner`, `provisionerConfig`,
  # `kubernetes`, `network`, `kubeContext`, the service and verify blocks and
  # the runtime contexts all reach `cata` through `cliConfig` and appear in no
  # other fixture. A refactor of the cluster descriptor could rewrite every one
  # of them and no check would move.
  #
  # Diffed against `nix/cli-configs.nix` rather than recomputed, so this and
  # `refresh-cli-configs` read one store path instead of two pipelines.
  cliConfigCheck =
    name: _lab:
    pkgs.runCommand "cliConfig-${name}" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
      if ! diff -u ${cliConfigDir}/${name}.json ${cliConfigs}/${name}.json; then
        echo "" >&2
        echo "The document cata parses for ${name} changed." >&2
        echo "This is the lab as the CLI sees it: how each cluster is" >&2
        echo "provisioned, on what ranges, under which context, and what the" >&2
        echo "runner is told to stand up. None of it appears in the manifest" >&2
        echo "digest, so this is the only place a change to it shows." >&2
        echo "" >&2
        echo "If intended, refresh it and read the diff:" >&2
        echo "" >&2
        echo "  nix run .#refresh-cli-configs" >&2
        exit 1
      fi
      touch $out
    '';

  # Every image the lab pulls comes from a registry the cache sits in front of.
  #
  # `lab.registry.upstreams` is both the zot sync sources and the `mirrors:`
  # entries in the `registries.yaml` every node mounts. An image from a
  # registry with no entry is not merely uncached: containerd goes to the
  # public registry directly and has to resolve the name itself, which a node
  # cannot do once the lab runs its own DNS — that server is authoritative for
  # the zone and answers REFUSED for everything else, which a resolver treats
  # as an answer rather than a reason to ask elsewhere. The pull fails on a
  # name that resolves perfectly well from the host.
  #
  # `lab.registry.upstreams` says "add one when a floe pulls from an upstream
  # not listed here" and nothing enforced it. Every lab passes today; this
  # exists for the floe that adds a registry and not the entry.
  #
  # Reads `images.txt` from the built package rather than the component
  # channel, because that file is what `warm-cache` iterates and it includes
  # the images scraped out of charts that no floe declared.
  imageUpstreamCheck =
    name: lab:
    let
      hosts = map (u: u.host) lab.config.lab.registry.upstreams;
    in
    pkgs.runCommand "${name}-images-are-cacheable" { nativeBuildInputs = [ pkgs.gawk ]; } ''
      # A first path component is a registry only where it looks like a host —
      # a dot, a port, or `localhost`. Everything else is a Docker Hub
      # namespace and the image is implicitly `docker.io/...`, which is how
      # `chrislusf/seaweedfs` and `velero/velero` reach the mirror.
      awk -F/ '{ if (NF > 1 && ($1 ~ /[.:]/ || $1 == "localhost")) print $1; else print "docker.io" }' \
        ${lab.config.lab.out.package}/images.txt | LC_ALL=C sort -u > $TMPDIR/used

      printf '%s\n' ${lib.escapeShellArgs hosts} | LC_ALL=C sort -u > $TMPDIR/mirrored

      if ! missing=$(comm -23 $TMPDIR/used $TMPDIR/mirrored) || [ -n "$missing" ]; then
        echo "${name} pulls from registries the lab's cache does not mirror:" >&2
        echo "$missing" | sed 's/^/  /' >&2
        echo "" >&2
        echo "Each becomes a direct pull, and a node that resolves through the" >&2
        echo "lab's own DNS cannot resolve the name — that server is authoritative" >&2
        echo "for the zone and answers REFUSED for everything else. Add an entry to" >&2
        echo "lab.registry.upstreams for each." >&2
        exit 1
      fi
      touch $out
    '';

  perLab =
    lib.concatLists (
      lib.mapAttrsToList (
        name: lab:
        lib.optional lab.config.lab.registry.enable {
          "${name}-images-are-cacheable" = imageUpstreamCheck name lab;
        }
      ) labDefs
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (name: lab: [
        { "${name}-eval" = evalCheck name lab; }
        { "manifest-digest-${name}" = digestCheck name lab; }
        { "${name}-declared-bundles" = declaredBundlesCheck name lab; }
        { "${name}-renders-no-secret-material" = secretMaterialCheck name lab; }
        { "${name}-lint" = lintCheck name lab; }
        { "plan-deploy-${name}" = planSnapshotCheck name lab "deploy"; }
        { "plan-teardown-${name}" = planSnapshotCheck name lab "teardown"; }
        { "cliConfig-${name}" = cliConfigCheck name lab; }
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
          # Only the clusters the lab is the edge for. One that is its own
          # edge (RFC 0005 §6.4) routes its hostnames itself, so the lab's
          # proxy having no backend for them is the arrangement rather than
          # the fault.
          routed = lib.unique (
            lib.concatLists (
              lib.mapAttrsToList (
                _: c:
                lib.optionals (c.edge.mode == "proxy") (
                  map (h: h.host) (lib.filter (h: h.tier == "public") c.out.exposedHosts)
                )
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

  # ---- between clusters, inside one lab ----------------------------------
  #
  # RFC 0005 §5 names both of these as lab-level checks and neither existed
  # while every runnable lab had one cluster. `homelab` has two, and both
  # failures are silent: the first at runtime with routing that half works,
  # the second with a 503 from a backend nobody meant to reach.

  # Every range a cluster claims, with something to call it in a message.
  # `out.cluster` is the descriptor the provisioner emitted, so this is the
  # range the cluster is actually created with rather than the input someone
  # meant to pass.
  # Only the clusters that share the lab's docker network.
  #
  # The whole fault here is one network handing out two identical addresses.
  # A cluster in a cloud is on its own network entirely, so its ranges may
  # overlap another's freely — and refusing that would refuse the ordinary
  # arrangement of a local cluster and a managed one, which both take the
  # provider's defaults and both are right to.
  #
  # `provider` is the descriptor's own answer, the same fact
  # `modules/lab/plan.nix` uses to decide whether a cluster needs the network
  # at all.
  onLabNetwork = cluster: cluster.spec.provider == "docker";

  rangesOf =
    labName: clusterName: cluster:
    lib.optionals (onLabNetwork cluster) (
      lib.concatLists (
        lib.mapAttrsToList (_unit: descriptor: [
          {
            what = "${clusterName}'s pod range";
            cidr = descriptor.network.podSubnet;
          }
          {
            what = "${clusterName}'s service range";
            cidr = descriptor.network.serviceSubnet;
          }
        ]) cluster.out.cluster
      )
    );

  # Cross-cluster only, and every combination of the two kinds: on one docker
  # network a pod address from `core` and a service address from `obs` are as
  # capable of colliding as two pod ranges. Within one cluster the distribution
  # refuses the overlap itself.
  rangeClashes = lib.concatLists (
    lib.mapAttrsToList (
      labName: lab:
      let
        byCluster = lib.mapAttrs (rangesOf labName) lab.config.lab.clusters;

        pairs = lib.concatLists (
          lib.mapAttrsToList (
            a: rangesA:
            lib.concatLists (
              lib.mapAttrsToList (
                b: rangesB:
                lib.optionals (a < b) (
                  lib.concatMap (
                    ra: map (rb: { inherit ra rb; }) (lib.filter (rb: net.cidrsOverlap ra.cidr rb.cidr) rangesB)
                  ) rangesA
                )
              ) byCluster
            )
          ) byCluster
        );

        # The lab's own docker network is the third party every cluster shares,
        # and a cluster whose range covers the bridge cannot reach its own
        # gateway.
        vsDocker = lib.concatLists (
          lib.mapAttrsToList (
            _: ranges:
            map (r: "${labName}: ${r.what} (${r.cidr}) overlaps the lab's docker network (${subnetOf lab})") (
              lib.filter (r: net.cidrsOverlap r.cidr (subnetOf lab)) ranges
            )
          ) byCluster
        );
      in
      map (p: "${labName}: ${p.ra.what} (${p.ra.cidr}) overlaps ${p.rb.what} (${p.rb.cidr})") pairs
      ++ vsDocker
    ) labDefs
  );

  # One hostname, two clusters the lab fronts. HAProxy emits a `use_backend`
  # line per exposed host and the first match wins, so the second cluster's
  # route is unreachable and nothing anywhere says so.
  #
  # Only clusters the lab is the edge for, because that is the whole of the
  # fault: it is HAProxy's ordering, and a cluster HAProxy has no row for
  # cannot lose to another. A lab that serves a name locally while something
  # else serves it for a self-edge cluster (RFC 0005 §6.4) is the arrangement
  # rather than the collision — one name, two edges, and only one of them
  # here. Counting those as a clash would refuse exactly the setup the mode
  # exists to allow.
  hostClashes = lib.concatLists (
    lib.mapAttrsToList (
      labName: lab:
      let
        claimsHere = lib.concatLists (
          lib.mapAttrsToList (
            clusterName: c:
            lib.optionals (c.edge.mode == "proxy") (
              map (h: {
                inherit clusterName;
                inherit (h) host;
              }) (lib.filter (h: h.tier == "public") c.out.exposedHosts)
            )
          ) lab.config.lab.clusters
        );
      in
      lib.concatMap (
        host:
        let
          holders = lib.unique (map (c: c.clusterName) (lib.filter (c: c.host == host) claimsHere));
        in
        lib.optional (lib.length holders > 1) (
          "${labName}: '${host}' is routed by ${lib.concatStringsSep " and " holders}"
        )
      ) (lib.unique (map (c: c.host) claimsHere))
    ) labDefs
  );

  # ---- a value the lab holds twice -----------------------------------------
  #
  # A lab has no way to project a value out of its own configuration: every
  # path into `lab.secrets.managed` reads from a store. Where a floe needs one
  # anyway — external-dns and the TSIG key Knot is configured with — the lab
  # writes it in the env file as well, and the two have to agree.
  #
  # Nothing at runtime would say they do not. The controller starts, every
  # update comes back NOTAUTH, and it logs that below the default level.
  #
  # Parsed rather than templated: the env file is what `cata` actually reads,
  # so comparing against anything else would compare against a copy.
  tsigKeyClashes = lib.concatLists (
    lib.mapAttrsToList (
      labName: lab:
      let
        c = lab.config.lab;

        # Only labs that route the key into a cluster. One with no such
        # projection holds the key in a single place and has nothing to
        # disagree with.
        projected = lib.concatLists (
          lib.mapAttrsToList (
            clusterName: cluster:
            lib.mapAttrsToList (_name: p: { inherit clusterName; }) (
              lib.filterAttrs (_: p: p.source == "externaldns-tsig") cluster.secrets.project
            )
          ) c.clusters
        );

        envFile = if c.secrets.envFile == null then null else ../../. + "/${c.secrets.envFile}";

        # `NAME='value'` or `NAME=value`, last assignment wins, comments and
        # blank lines skipped — which is as much of a shell env file as `cata`
        # itself reads.
        valueIn =
          path: varName:
          let
            lines = lib.filter (l: lib.hasPrefix "${varName}=" (lib.removePrefix " " l)) (
              lib.splitString "\n" (builtins.readFile path)
            );
          in
          if lines == [ ] then
            null
          else
            lib.removeSuffix "'" (lib.removePrefix "'" (lib.removePrefix "${varName}=" (lib.last lines)));

        # The variable name is derived from the store the secret sits in, and
        # the two labs that hold this key put it in different stores. Both
        # names are tried rather than the store being restated here, where it
        # would be a third copy of the same fact.
        varNames = [
          "CATA_SECRET_AUTHORED__EXTERNALDNS_TSIG__TSIG_SECRET"
          "CATA_SECRET_KNOT__EXTERNALDNS_TSIG__TSIG_SECRET"
        ];

        found =
          if envFile == null then
            null
          else
            lib.findFirst (v: v != null) null (map (valueIn envFile) varNames);
      in
      lib.optionals (projected != [ ]) (
        lib.optional (
          envFile == null
        ) "${labName} projects the external-dns TSIG key and names no lab.secrets.envFile to take it from"
        ++ lib.optional (envFile != null && found == null) (
          "${labName}'s env file sets no TSIG key "
          + "under any name derived from a store it could be in, so the projected Secret is "
          + "empty and every RFC2136 update is refused"
        )
        ++ lib.optional (found != null && found != c.dns.tsigSecret) (
          "${labName}: the TSIG key in ${c.secrets.envFile} is not the one Knot is configured with "
          + "at lab.dns.tsigSecret — external-dns will authenticate against a key the server "
          + "does not have"
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

  lab-cluster-ranges =
    refuse "lab-cluster-ranges"
      "Two clusters on one docker network need ranges that do not overlap, and neither one can overlap the network itself. An address plan is a decision written down (RFC 0005 §5); nothing derives these, so nothing catches them but this."
      rangeClashes;

  lab-tsig-key-agrees =
    refuse "lab-tsig-key-agrees"
      "The lab holds this key twice — once for Knot, once for the Secret external-dns reads — because a lab cannot project a value out of its own configuration. Nothing at runtime reports a mismatch: the controller starts, every update is refused, and it says so below the default log level."
      tsigKeyClashes;

  lab-routed-hosts-are-unique =
    refuse "lab-routed-hosts-are-unique"
      "Two clusters routing one hostname is not a choice the ingress can make. It emits a `use_backend` per exposed host and the first match wins, so the second cluster's route is unreachable and nothing reports it."
      hostClashes;
}
