# external-dns: Kubernetes objects in, DNS records out.
#
# Rebuilt against RFC 0001, and the first floe to contribute a plan step. That
# step is the reason it comes back now: with `policy = "sync"`, external-dns
# owns the records it created, and destroying the cluster out from under it
# leaves them in the zone forever — nothing is left to notice they should go.
# The step deletes what external-dns watches and waits for the queue to drain
# before the cluster is torn down.
#
# Two things the parked floe did that are not carried forward:
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
  catallaxy,
  lib,
  pkgs,
  floe,
  sigs,
  kinds,
  ...
}:

let
  t = import ../../../lib/plan-tokens.nix { inherit lib; };
  duration = import ../../../lib/util/duration.nix { inherit lib; };
in

catallaxy.mkComponentFloe {
  name = "external-dns";
  summary = "external-dns, publishing routed hostnames into the lab's zone over RFC2136.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Addresses every record points at, regardless of what the object says.

        A lab behind one ingress needs this: the LoadBalancer address a k3d
        Service reports is a cluster-internal address that nothing outside can
        reach.
      '';
    };
  };

  # Which zone to publish into and where its server listens. The same three
  # facts `lab-dns` needs, from the same place, so the two cannot be told
  # different things about one lab.
  requires.zone = sigs.DNS_ZONE;
  requires.gatewayApi = sigs.GATEWAY_API;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;
        zone = config.floe.requires.zone;
        cluster = config.floe.requires.cluster;

        secretParts = lib.splitString "/" inputs.tsigSecretRef;
        secretNamespace = lib.head secretParts;
        secretName = lib.last secretParts;

        intervalSeconds = duration.toSeconds "external-dns.interval" inputs.interval;

        # Two intervals plus a margin, capped. Long enough that a reconcile in
        # flight when teardown starts still gets to finish; short enough that a
        # controller which is never going to drain does not hold the teardown
        # open. The cap is what stops a lab with a 10m interval blocking for
        # 20m on a cluster that is about to be deleted anyway.
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

            deadline=$(( $(date +%s) + ${toString drainDeadline} ))
            while [ "$(date +%s)" -lt "$deadline" ]; do
              m=$(metrics) || m=""
              if [ -n "$m" ] \
                && metric_is_zero "$m" external_dns_registry_endpoints_total \
                && metric_is_zero "$m" external_dns_source_endpoints_total; then
                echo "external-dns reports no endpoints; records drained"
                exit 0
              fi
              sleep 5
            done

            echo "external-dns did not report an empty registry within ${toString drainDeadline}s" >&2
            echo "records may be left in the zone" >&2
            exit 1
          '';
        };
      in
      {
        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          # `sync` is the only policy that deletes, so it is the only one that
          # can leave anything behind. Declared conditionally for that reason
          # and not as a matter of taste: a teardown step that has nothing to
          # do still costs the drain wait.
          steps = lib.optionalAttrs (inputs.policy == "sync") {
            purge-records = {
              kind = "run-script";
              direction = "teardown";
              description = "Delete external-dns-watched objects and wait for records to drain";
              provides = [ t.lab.cleanup ];

              # Before the cluster goes: the drain wait reads external-dns's
              # own metrics endpoint, which needs the controller running.
              before = [ (t.wants (t.cluster cluster.name).destroyed) ];

              # A zone left dirty is bad; a lab that cannot be destroyed is
              # worse. This is the one step whose failure must not stop the
              # teardown, because everything after it is what frees the ports
              # and the docker network.
              policy.onFailure = "continue";
              params.bin = "${purge}/bin/external-dns-purge-records";
            };
          };

          bundles.external-dns = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            # The Secret is the lab's to supply — a projection, or another
            # floe. Named here so the cluster's coherence check refuses a lab
            # that enables this floe and never lands the key, instead of a
            # controller that starts and is refused by the DNS server.
            needsSecrets = [ inputs.tsigSecretRef ];

            images.controller = {
              registry = "registry.k8s.io";
              repository = "external-dns/external-dns";
              tag = "v0.16.1";
              digest = null;
            };

            helmCharts.external-dns = {
              chart = inputs.chart;
              releaseName = "external-dns";
              namespace = inputs.namespace;
              values = {
                provider.name = "rfc2136";
                inherit (inputs) sources policy interval;
                domainFilters = [ zone.zone ];

                # The cluster's own name. Two clusters publishing into one
                # zone each need to know which records are theirs, and the
                # default — the release name — is the same in both.
                txtOwnerId = cluster.name;
                txtPrefix = "extdns-";

                extraArgs = [
                  "--rfc2136-host=${zone.server}"
                  "--rfc2136-port=${toString zone.port}"
                  "--rfc2136-zone=${zone.zone}"
                  "--rfc2136-tsig-keyname=${inputs.tsigKeyname}"
                  "--rfc2136-tsig-secret-alg=${inputs.tsigSecretAlg}"
                ]
                ++ lib.optional (
                  inputs.defaultTargets != [ ]
                ) "--default-targets=${lib.concatStringsSep "," inputs.defaultTargets}";

                # The one argument that is not an argument. `--rfc2136-tsig-secret`
                # would put the key in the Deployment's argv, where anyone with
                # `get pod` can read it and where the rendered manifest carries
                # it into the store.
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

            ready = {
              kind = "condition";
              resource = "deployment/external-dns";
              namespace = inputs.namespace;
              condition = "Available";
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
            # The trailing-dot check used to be here. It is `T.dnsName` on
            # `DNS_ZONE.zone` now — refused where the zone is decided rather
            # than in whichever consumer happened to look.
          ];
        };
      }
    )
  ];
}
