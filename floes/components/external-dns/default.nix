# external-dns: Kubernetes objects in, DNS records out.
#
# The one floe that contributes a plan step. That
# step is the reason it comes back now: with `policy = "sync"`, external-dns
# owns the records it created, and destroying the cluster out from under it
# leaves them in the zone forever — nothing is left to notice they should go.
# The step deletes what external-dns watches and waits for the queue to drain
# before the cluster is torn down.
#
# Two things it deliberately does not do:
#
#   - The TSIG secret was a plain option interpolated into `extraArgs`, which
#     renders it into the Deployment's argv. That is secret material in a
#     manifest, and `nix/checks/lab-checks.nix`'s `secret-material` rule would
#     refuse it. It now arrives as an environment variable from a Secret, which
#     is what `needsSecrets` is for.
#
#   - Six providers' worth of options, of which the example labs used one.
#     `rfc2136` is the provider a lab can actually run against its own
#     resolver; the cloud ones are credentials-and-a-zone and belong to
#     whoever brings the credentials.
{
  floe,
  upstream ? null,
  lib,
  pkgs,
  sigs,
  kinds,
  ...
}:

let
  duration = import ../../../lib/util/duration.nix { inherit lib; };
in

floe.mkFloe {
  name = "external-dns";
  summary = "external-dns, publishing routed hostnames into the lab's zone over RFC2136.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${upstream.chart}";
      defaultText = lib.literalExpression "upstream.chart";
      description = "Store path of the external-dns Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "external-dns";
      description = "Namespace the controller runs in.";
    };

    tsigKeyname = lib.mkOption {
      type = lib.types.str;
      default = "externaldns-key";
      description = "TSIG key name the server knows this client by.";
    };

    tsigSecretRef = lib.mkOption {
      type = lib.types.str;
      description = ''
        `<namespace>/<name>` of a Secret with a `tsig-secret` key holding the
        base64 TSIG secret. Required.

        A reference rather than the value: external-dns reads it from
        `EXTERNAL_DNS_RFC2136_TSIG_SECRET`, so it never has to appear in a
        rendered manifest.
      '';
    };

    tsigSecretAlg = lib.mkOption {
      type = lib.types.enum [
        "hmac-sha256"
        "hmac-sha512"
        "hmac-sha1"
      ];
      default = "hmac-sha256";
      description = "TSIG algorithm. Must match what the server is configured with.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "1m";
      description = "How often the reconcile loop runs when nothing has happened.";
    };

    sources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "service"
        "ingress"
        "gateway-httproute"
        "gateway-tlsroute"
      ];
      description = "Object kinds to derive records from.";
    };

    policy = lib.mkOption {
      type = lib.types.enum [
        "sync"
        "upsert-only"
        "create-only"
      ];
      default = "sync";
      description = ''
        `sync` creates, updates and deletes. It is the only one that keeps the
        zone honest, and the only one that needs the teardown step: a record
        this controller created outlives the cluster otherwise.
      '';
    };

    defaultTargets = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      defaultText = lib.literalExpression "the zone's own server";
      description = ''
        Addresses every record points at, regardless of what the object says.

        A lab behind one ingress needs this: the LoadBalancer address a k3d
        Service reports is a cluster-internal address that nothing outside can
        reach.

        Null takes the address the zone's server answers on, which is that
        ingress. A lab was threading its own `network.gateway` in here by
        hand, and `DNS_ZONE` already carries the same address — so the two
        could disagree and the records would point somewhere nothing serves.
        An explicit `[ ]` publishes whatever each object reports.
      '';
    };
  };

  # Which zone to publish into and where its server listens. The same three
  # facts `coredns-zone` needs, from the same place, so the two cannot be told
  # different things about one lab.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.zone = sigs.DNS_ZONE;
  requires.gatewayApi = sigs.GATEWAY_API;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        zone = config.floe.requires.zone;
        cluster = config.floe.requires.cluster;

        targets = if inputs.defaultTargets != null then inputs.defaultTargets else [ zone.server ];

        secretParts = lib.splitString "/" inputs.tsigSecretRef;
        secretNamespace = lib.head secretParts;
        secretName = lib.last secretParts;

        intervalSeconds = duration.toSeconds "external-dns.interval" inputs.interval;

        drainDeadline = lib.min 180 (2 * intervalSeconds + 30);

        purge = pkgs.writeShellApplication {
          name = "external-dns-purge-records";
          runtimeInputs = [
            pkgs.kubectl
            pkgs.coreutils
            pkgs.gawk
          ];
          text = ''
            CONTEXT=${lib.escapeShellArg cluster.context}

            # A teardown runs against a cluster that may already be gone, and
            # a purge that cannot reach it has nothing to purge. Not an error:
            # `destroy` after a failed `up` is the ordinary case.
            if ! kubectl --context "$CONTEXT" get --raw=/healthz >/dev/null 2>&1; then
              echo "cluster $CONTEXT unreachable; nothing to purge"
              exit 0
            fi

            echo "purging external-dns-watched objects on $CONTEXT"

            for crd in httproutes.gateway.networking.k8s.io tlsroutes.gateway.networking.k8s.io; do
              if kubectl --context "$CONTEXT" get crd "$crd" -o name >/dev/null 2>&1; then
                kubectl --context "$CONTEXT" delete "$crd" -A --all \
                  --ignore-not-found=true --wait=false 2>/dev/null || true
              fi
            done

            kubectl --context "$CONTEXT" delete ingress -A --all \
              --ignore-not-found=true --wait=false 2>/dev/null || true

            # Only LoadBalancer Services carry records, and only outside the
            # namespaces the cluster brought with it — deleting kube-dns
            # during a teardown breaks the very lookups the drain wait needs.
            kubectl --context "$CONTEXT" get svc -A \
              -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' \
              2>/dev/null | while IFS=/ read -r ns name; do
                [ -n "$ns" ] || continue
                case "$ns" in
                  kube-system|kube-public|kube-node-lease) continue ;;
                esac
                kubectl --context "$CONTEXT" -n "$ns" delete svc "$name" \
                  --ignore-not-found=true --wait=false 2>/dev/null || true
              done

            metrics() {
              kubectl --context "$CONTEXT" get --raw \
                "/api/v1/namespaces/${inputs.namespace}/services/external-dns:7979/proxy/metrics" \
                2>/dev/null
            }

            # Prometheus exposition is `name value` or `name{labels} value`.
            # Take the name by its own delimiter instead of assuming the whole
            # first field is the name: the moment external-dns puts a label on
            # either series below, `$1 == key` stops matching and this waits
            # out its full deadline every time, silently.
            metric() {
              printf '%s\n' "$1" | awk -v key="$2" '
                substr($0, 1, 1) == "#" { next }
                {
                  name = $1
                  brace = index(name, "{")
                  if (brace > 0) name = substr(name, 1, brace - 1)
                  if (name == key) { print $NF; exit }
                }
              '
            }

            # Numeric zero, whichever float spelling the exporter uses.
            metric_is_zero() {
              value=$(metric "$1" "$2")
              [ -n "$value" ] && awk -v v="$value" 'BEGIN { exit (v + 0 == 0) ? 0 : 1 }'
            }

            # Last seen, so the timeout below can say which of the two
            # failures this was: metrics that never became zero, or metrics
            # that were never readable. Both used to print the same line.
            reads=0
            last_registry="" last_source=""

            deadline=$(( $(date +%s) + ${toString drainDeadline} ))
            while [ "$(date +%s)" -lt "$deadline" ]; do
              m=$(metrics) || m=""
              if [ -n "$m" ]; then
                reads=$(( reads + 1 ))
                last_registry=$(metric "$m" external_dns_registry_endpoints_total)
                last_source=$(metric "$m" external_dns_source_endpoints_total)
                # The registry alone. It counts the records external-dns
                # *owns*, which is the question this step asks. Sources count
                # what it would create next, and one survives on purpose: the
                # loop above skips LoadBalancer Services in system namespaces,
                # because deleting kube-dns mid-teardown breaks the lookups
                # this wait depends on. Requiring both to be zero failed every
                # run with `registry=0 source=1` — a clean zone, reported as a
                # leak.
                if metric_is_zero "$m" external_dns_registry_endpoints_total; then
                  echo "external-dns owns no records; zone drained (sources still ''${last_source:-0})"
                  exit 0
                fi
              fi
              sleep 5
            done

            if [ "$reads" -eq 0 ]; then
              echo "could not read external-dns metrics in ${toString drainDeadline}s:" >&2
              echo "  ${inputs.namespace}/external-dns:7979/proxy/metrics answered nothing" >&2
              echo "so whether the records drained is unknown, not known to be false" >&2
            else
              echo "external-dns still owns records after ${toString drainDeadline}s" >&2
              echo "  registry_endpoints_total=''${last_registry:-<absent>}" >&2
              echo "  source_endpoints_total=''${last_source:-<absent>}" >&2
              echo "read the metrics $reads time(s); an absent series means the" >&2
              echo "exporter renamed it and this waited out the deadline for nothing" >&2
            fi
            echo "records may be left in the zone" >&2
            exit 1
          '';
        };
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          steps = lib.optionalAttrs (inputs.policy == "sync") {
            purge-records = {
              kind = "run-script";
              direction = "teardown";
              description = "Delete external-dns-watched objects and wait for records to drain";
              teardown = "before-cluster-destroy";

              policy.onFailure = "continue";
              params.bin = "${purge}/bin/external-dns-purge-records";
            };
          };

          bundles.external-dns = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            needsSecrets = [ inputs.tsigSecretRef ];

            images.controller = kinds.mkImage "registry.k8s.io/external-dns/external-dns:v0.16.1";

            helmCharts.external-dns = kinds.mkHelmChart {
              chart = inputs.chart;
              releaseName = "external-dns";
              namespace = inputs.namespace;
              values = {
                provider.name = "rfc2136";
                inherit (inputs) sources policy interval;
                domainFilters = [ zone.zone ];

                txtOwnerId = cluster.name;
                txtPrefix = "extdns-";

                extraArgs = [
                  "--rfc2136-host=${zone.server}"
                  "--rfc2136-port=${toString zone.port}"
                  "--rfc2136-zone=${zone.zone}"
                  "--rfc2136-tsig-keyname=${inputs.tsigKeyname}"
                  "--rfc2136-tsig-secret-alg=${inputs.tsigSecretAlg}"
                ]
                ++ lib.optional (targets != [ ]) "--default-targets=${lib.concatStringsSep "," targets}";

                env = [
                  {
                    name = "EXTERNAL_DNS_RFC2136_TSIG_SECRET";
                    valueFrom.secretKeyRef = {
                      name = secretName;
                      key = "tsig-secret";
                    };
                  }
                ];
              };
            };

            ready = kinds.readyDeployment {
              name = "external-dns";
              namespace = inputs.namespace;
              timeout = "3m";
            };

            ops.dns = {
              records = kinds.mkOpsCommand {
                description = "Show what external-dns currently believes it owns";
                package = "${
                  pkgs.writeShellApplication {
                    name = "external-dns-records";
                    runtimeInputs = [ pkgs.kubectl ];
                    text = ''
                      kubectl --context ${lib.escapeShellArg cluster.context} \
                        -n ${lib.escapeShellArg inputs.namespace} \
                        get --raw \
                        "/api/v1/namespaces/${inputs.namespace}/services/external-dns:7979/proxy/metrics" \
                        | grep -E '^external_dns_(registry|source)_endpoints_total'
                    '';
                  }
                }/bin/external-dns-records";
              };
            };
          };

          assertions = [
            {
              assertion = secretNamespace == inputs.namespace;
              message =
                "tsigSecretRef is '${inputs.tsigSecretRef}', but the Deployment reads it "
                + "through a secretKeyRef, which only resolves within its own namespace "
                + "('${inputs.namespace}')";
            }
          ];
        };
      }
    )
  ];
}
