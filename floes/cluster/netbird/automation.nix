# The one credential nobody owns, and the operator that spends it.
#
# Everything else in this floe is declarative because something else
# reconciles it: kaniop owns the service account and rotates its token, and
# `netbird-operator` — a floe of its own, possibly in another cluster — owns
# groups, setup keys, routers and network resources. Between the two sits a
# netbird personal access token, minted by netbird, owned by nobody, and
# expiring.
#
# So that is the only thing here that is a script, and the only thing that
# self-heals. The same script runs as a Job at install and as a CronJob after,
# and the first thing it does is ask netbird whether there is anything to do.
{
  lib,
  k8s,
  nb,
}:

let
  inherit (nb) namespace labels;

  patScript = builtins.readFile ./scripts/pat.sh;

  # What the script is told. Everything it needs and nothing it could work
  # out for itself, so a change here is a change in intent — which is what
  # `mkIdempotentJob` hashes to decide whether the Job runs again.
  env = [
    {
      name = "NB_NS";
      value = namespace;
    }
    {
      name = "NB_URL";
      # The Service, not the routed name: this runs in the cluster beside
      # management, and the routed name would leave and come back through the
      # ingress to reach a pod one hop away.
      value = nb.managementInternalUrl;
    }
    {
      name = "OUT_SECRET";
      value = nb.patSecret;
    }
    {
      name = "OUT_KEY";
      value = nb.patKey;
    }
    {
      name = "SA_NS";
      value = nb.serviceAccount.token.namespace;
    }
    {
      name = "SA_SECRET";
      value = nb.serviceAccount.token.name;
    }
    {
      name = "SA_KEY";
      value = nb.serviceAccount.token.key;
    }
    {
      name = "CLIENT_ID";
      value = nb.oidc.clientId;
    }
    {
      name = "TOKEN_ENDPOINT";
      value = nb.oidc.tokenEndpoint;
    }
    {
      name = "CA_FILE";
      value = "${nb.caBundle.mountPath}/${nb.caBundle.filename}";
    }
    {
      name = "TOKEN_NAME";
      value = "catallaxy-operator";
    }
    {
      # Shorter than the rotation period of the credential that mints it, so
      # the heal has run several times before anything expires.
      name = "TOKEN_DAYS";
      value = "365";
    }
  ];

  volumes = [
    {
      name = nb.caBundle.volumeName;
      configMap = {
        inherit (nb.caBundle) name;
        items = [
          {
            inherit (nb.caBundle) key;
            path = nb.caBundle.filename;
          }
        ];
      };
    }
  ];

  container = {
    name = "pat";
    image = nb.images.tools;
    command = [
      "sh"
      "-c"
      patScript
    ];
    inherit env;
    volumeMounts = [
      {
        name = nb.caBundle.volumeName;
        mountPath = nb.caBundle.mountPath;
        readOnly = true;
      }
    ];
  };

  podSpec = {
    serviceAccountName = "netbird-pat";
    restartPolicy = "OnFailure";
    containers = [ container ];
    inherit volumes;
  };

  idempotent = import ../../../lib/util/idempotent-job.nix { inherit lib; };

  # Named after a hash of what it was *asked for*, so it runs again when the
  # intent changes and not when the script is reformatted. A Job is immutable;
  # without that, a re-render either collides with the existing one or leaves
  # a stale one behind.
  bootstrap = idempotent.mkIdempotentJob {
    name = "netbird-pat";
    inherit namespace;

    contentInputs = {
      url = nb.managementInternalUrl;
      client = nb.oidc.clientId;
      out = "${nb.patSecret}/${nb.patKey}";
      sa = "${nb.serviceAccount.token.name}/${nb.serviceAccount.token.key}";
    };

    inherit podSpec;
  };

  rbac = {
    netbird-pat-sa = k8s.serviceAccount "netbird-pat";

    # It reads the service account's token and writes the one it mints. Two
    # verbs on one namespace, which is the whole of what it may do.
    netbird-pat-role = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "Role";
      metadata = {
        name = "netbird-pat";
        inherit namespace labels;
      };
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "secrets" ];
          verbs = [
            "get"
            "create"
            "update"
            "patch"
          ];
        }
      ];
    };

    netbird-pat-binding = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "RoleBinding";
      metadata = {
        name = "netbird-pat";
        inherit namespace labels;
      };
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "Role";
        name = "netbird-pat";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "netbird-pat";
          inherit namespace;
        }
      ];
    };
  };
in
{
  # The identity, the token it mints, and the schedule that keeps it true.
  resources =
    rbac
    // {
      netbird-service-account = nb.serviceAccount.resource;
    }
    // bootstrap.resources
    // {
      # The heal. Same script, asked on a schedule, and a no-op every time
      # until the token stops being accepted.
      #
      # Hourly rather than continuously: the failure it recovers from is a
      # credential expiring or being revoked, which is not a thing that
      # happens between two minutes. `concurrencyPolicy: Forbid` so a slow run
      # against an unreachable management does not stack up behind itself.
      netbird-pat-heal = {
        apiVersion = "batch/v1";
        kind = "CronJob";
        metadata = {
          name = "netbird-pat-heal";
          inherit namespace labels;
        };
        spec = {
          schedule = "17 * * * *";
          concurrencyPolicy = "Forbid";
          successfulJobsHistoryLimit = 1;
          failedJobsHistoryLimit = 3;
          startingDeadlineSeconds = 300;
          jobTemplate.spec.template.spec = podSpec;
        };
      };
    };

  inherit podSpec;
}
