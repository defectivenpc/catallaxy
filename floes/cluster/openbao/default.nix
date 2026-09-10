# OpenBao: a KV server the lab can use as a runtime secret store.
#
# `standalone` with file storage, not `dev`. Dev mode is in-memory and its
# root token is a Helm value — so it loses every secret on restart, and the
# token renders into the Deployment's argv where `secret-material` refuses it.
# A store that forgets is not a store.
#
# That makes initialisation real work: a fresh vault has no secrets engine, no
# policy and no token, and it is sealed. `scripts/init.sh` does all of it, run
# as an idempotent Job so a re-render does not re-run it against a live API.
#
# What this floe does not do is come back from a restart on its own. A
# shamir-sealed vault is sealed again the moment its pod moves, and unsealing
# needs the keys, which are deliberately not in the cluster the vault protects.
# `autoUnseals = false` on the signature says so, and
# `cata lab ops secrets openbao-init-unseal` is how a human does it. The
# `init-` in that name is the bundle the command sits on, which the operator
# surface folds in (`elaborate.nix:322-331`) — `docs/floes/openbao.md` is
# generated from what the command actually becomes, so the two cannot drift
# again. Auto-unseal needs a KMS, which a lab on one docker host does not have.
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
  hcl = import ../../../lib/util/hcl.nix { inherit lib; };
  idempotent = import ../../../lib/kubernetes/idempotent-job.nix { inherit lib; };
in

catallaxy.mkComponentFloe {
  name = "openbao";
  summary = "OpenBao, a Vault-compatible server, with its KV mount initialised.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the OpenBao Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "openbao";
      description = "Namespace the server runs in.";
    };

    storage = lib.mkOption {
      type = lib.types.str;
      default = "1Gi";
      description = "Size of the volume the file backend writes to.";
    };

    kvPath = lib.mkOption {
      type = lib.types.str;
      default = "secret";
      description = "Mount path of the KV engine this lab writes under.";
    };

    kvVersion = lib.mkOption {
      type = lib.types.enum [
        "v1"
        "v2"
      ];
      default = "v2";
      description = ''
        KV engine version.

        An enum though the API takes a string, because mounting a v2 engine
        and addressing it as v1 succeeds and stores the wrong shape — nothing
        notices until a reader gets an envelope where it expected a value.
      '';
    };

    tokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "openbao-token";
      description = ''
        Secret the init Job writes the scoped token into.

        Read by whatever authenticates to this store. It lands in
        `secretNamespace`, which is usually the external-secrets namespace
        rather than this one.
      '';
    };

    secretNamespace = lib.mkOption {
      type = lib.types.str;
      default = "external-secrets";
      description = "Namespace the token Secret is written to.";
    };
  };

  provides.vault = sigs.VAULT_SERVER;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        host = "openbao.${inputs.namespace}.svc.cluster.local";
        address = "http://${host}:8200";

        initSa = "openbao-init";

        # Rendered rather than written as a string, so a port stays a number
        # and a flag stays a bool. The renderer this replaced quoted
        # everything through `toString`: `tls_disable = ""` is what `false`
        # became, and HCL reads that as unset.
        serverConfig =
          hcl.body "" { ui = true; }
          + hcl.block "listener" "tcp" {
            tls_disable = 1;
            address = "[::]:8200";
            cluster_address = "[::]:8201";
          }
          + hcl.block "storage" "file" { path = "/openbao/data"; };

        # Two Roles because the Job writes into two namespaces: it reads and
        # writes the token Secret where external-secrets will look for it, and
        # that is not where OpenBao runs.
        rbacIn = ns: suffix: {
          "openbao-init-role-${suffix}" = {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "Role";
            metadata = {
              name = "openbao-init";
              namespace = ns;
            };
            rules = [
              {
                apiGroups = [ "" ];
                resources = [ "secrets" ];
                verbs = [
                  "get"
                  "create"
                  "patch"
                  "update"
                ];
              }
            ];
          };
          "openbao-init-rb-${suffix}" = {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "RoleBinding";
            metadata = {
              name = "openbao-init";
              namespace = ns;
            };
            roleRef = {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Role";
              name = "openbao-init";
            };
            subjects = [
              {
                kind = "ServiceAccount";
                name = initSa;
                namespace = inputs.namespace;
              }
            ];
          };
        };

        initImage = "docker.io/alpine/k8s:1.31.4";

        job = idempotent.mkIdempotentJob {
          name = "openbao-init";
          namespace = inputs.namespace;

          # What the Job was asked to do. Not the image, not the script: a
          # rebuilt base or a reformatted line is not a change of intent, and
          # re-running this against a live vault is what the hash exists to
          # prevent.
          contentInputs = {
            inherit (inputs)
              kvPath
              kvVersion
              tokenSecret
              secretNamespace
              ;
          };

          podSpec = {
            serviceAccountName = initSa;
            restartPolicy = "OnFailure";
            containers = [
              {
                name = "init";
                image = initImage;
                command = [
                  "bash"
                  "-c"
                ];
                args = [ (builtins.readFile ./scripts/init.sh) ];
                env = [
                  {
                    name = "BAO_ADDR";
                    value = address;
                  }
                  {
                    name = "NS";
                    value = inputs.namespace;
                  }
                  {
                    name = "KV_PATH";
                    value = inputs.kvPath;
                  }
                  {
                    name = "KV_VERSION";
                    value = inputs.kvVersion;
                  }
                  {
                    name = "TOKEN_SECRET";
                    value = inputs.tokenSecret;
                  }
                  {
                    name = "TOKEN_KEY";
                    value = "token";
                  }
                  {
                    name = "TOKEN_NS";
                    value = inputs.secretNamespace;
                  }
                  {
                    # No KMS on a lab's docker host, so there is nothing to
                    # auto-unseal against. The Job unseals inline with the
                    # keys it just generated, and prints them once.
                    name = "SEAL_MODE";
                    value = "shamir";
                  }
                ];
              }
            ];
          };
        };

        opsScript =
          name: text:
          "${
            pkgs.writeShellApplication {
              name = "openbao-${name}";
              runtimeInputs = [
                pkgs.kubectl
                pkgs.jq
              ];
              text = ''
                NS=${lib.escapeShellArg inputs.namespace}
                export NS
                ${text}
              '';
            }
          }/bin/openbao-${name}";
      in
      {
        config.floe.provides.vault = {
          inherit address;
          inherit (inputs) kvPath kvVersion;
          tokenSecret = {
            namespace = inputs.secretNamespace;
            name = inputs.tokenSecret;
            key = "token";
          };

          # See the header. Shamir, because there is no KMS to seal against,
          # so a restarted pod is a sealed vault until somebody opens it.
          autoUnseals = false;
        };

        config.floe.out.component = kinds.mkComponent {
          imagesComplete = true;

          # A consumer's token is only good once the Job has written it, and
          # the Job cannot run until the server answers. Naming both here is
          # what orders a consumer after the whole of it without naming
          # either bundle.
          backs.vault = [
            "server"
            "init"
          ];

          bundles.server = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            images.openbao = {
              registry = "quay.io";
              repository = "openbao/openbao";
              # The chart's own pin, not a guess. The first one here was
              # "2.4.1" and the image gate caught it.
              tag = "2.3.1";
              digest = null;
            };

            helmCharts.openbao = kinds.mkHelmChart {
              inherit (inputs) chart;
              releaseName = "openbao";
              namespace = inputs.namespace;
              values = {
                server = {
                  standalone = {
                    enabled = true;
                    config = serverConfig;
                  };
                  dataStorage = {
                    enabled = true;
                    size = inputs.storage;
                  };
                  # The chart's own readiness probe is `bao status`, which
                  # fails until the vault is initialised *and* unsealed —
                  # neither of which has happened when the pod first starts.
                  # Left on, nothing would ever become Ready and the init Job
                  # would never get a server to talk to.
                  readinessProbe.enabled = false;
                };
                injector.enabled = false;
              };
            };

            # `exists`, not `condition`: see above. A StatefulSet whose pod is
            # running is as much as can be true before the Job runs.
            ready = {
              kind = "exists";
              resource = "statefulset/openbao";
              namespace = inputs.namespace;
              timeout = "5m";
            };
          };

          bundles.init = kinds.mkBundle {
            needs = [ "server" ];

            images.init = kinds.mkImage "docker.io/alpine/k8s:1.31.4";

            resources = {
              "${initSa}" = {
                apiVersion = "v1";
                kind = "ServiceAccount";
                metadata = {
                  name = initSa;
                  namespace = inputs.namespace;
                };
              };
            }
            // rbacIn inputs.namespace "own"
            // rbacIn inputs.secretNamespace "token"
            // job.resources;

            # The Job mints it and writes it, so nothing in the rendered
            # manifests names it as a read. Declared so the cluster's
            # coherence check knows it will exist.
            secrets = [ "${inputs.secretNamespace}/${inputs.tokenSecret}" ];

            ready = kinds.readyCondition {
              resource = "job/${job.name}";
              condition = "Complete";
              namespace = inputs.namespace;
              timeout = "10m";
            };

            ops.secrets = {
              unseal = kinds.mkOpsCommand {
                description = "Unseal a restarted vault (needs the keys init printed)";
                args = [
                  {
                    name = "key";
                    description = "An unseal key. Repeat until the threshold is met.";
                    variadic = true;
                  }
                ];
                package = opsScript "unseal" (builtins.readFile ./scripts/ops-unseal.sh);
              };

              status = kinds.mkOpsCommand {
                description = "Whether the vault is initialised, sealed, and who the leader is";
                package = opsScript "status" (builtins.readFile ./scripts/ops-status.sh);
              };
            };
          };

          assertions = [
            {
              assertion = inputs.secretNamespace != inputs.namespace;
              message =
                "secretNamespace is '${inputs.secretNamespace}', the same namespace OpenBao runs "
                + "in. The token is for something else to authenticate with, and keeping it beside "
                + "the server it opens defeats the scoping — put it where the reader is";
            }
          ];
        };
      }
    )
  ];
}
