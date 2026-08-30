# The deployment and teardown plans, written out rather than derived.
#
# The parked system had a planner: 34 step kinds, an anchor grammar, and a
# topological sort over published tokens. That machinery earns its place when
# floes contribute steps and the order between them is not obvious. Nothing
# contributes steps yet, and three of them in a fixed order is not a graph
# problem, so this is a list.
#
# When a floe needs to contribute a step, this is where the planner goes.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;

  clusters = config.lab.clusters;

  # `origin`, `description` and `cluster` are all optional on the wire;
  # `policy.retry` is the only required policy field. The retry class is the
  # step kind's, not the author's: `create-cluster` is `oneShot` because
  # running it twice is not the same as running it once.
  step =
    {
      name,
      kind,
      retry,
      description,
      cluster ? null,
      params ? { },
    }:
    {
      inherit
        name
        kind
        description
        params
        ;
      cluster = cluster;
      origin = "lab.plan";
      policy.retry = retry;
    };
in
{
  options.lab.out.deploymentPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab up` executes.";
  };

  options.lab.out.teardownPlan = mkOption {
    type = types.listOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Ordered steps `cata lab destroy` executes.";
  };

  config.lab.out.deploymentPlan = [
    (step {
      name = "docker-network-create";
      kind = "docker-network-create";
      retry = "idempotent";
      description = "Create docker network '${config.lab.name}'";
      params = {
        name = config.lab.name;
        subnet = config.lab.network.subnet;
        inherit (config.lab.network) gateway;
      };
    })
  ]

  # Before anything that could consume a value, and early enough that a lab
  # missing a secret fails in seconds rather than after a cluster exists.
  #
  # Authored stores only. A runtime store holds values the lab mints and is
  # read by external-secrets from inside the cluster, so there is nothing here
  # for the CLI to check and asking it to would fail on a backend it
  # deliberately cannot open.
  ++ lib.optional (config.lab.secrets.managed != { }) (step {
    name = "ensure-secrets";
    kind = "ensure-secrets";
    retry = "idempotent";
    description = "Check the lab's authored secret stores are readable";
    params.stores = lib.attrNames (
      lib.filterAttrs (_: s: s.direction == "authored") config.lab.secrets.stores
    );
  })

  # Before the services, because the ingress bind-mounts the certificate this
  # writes and a container cannot mount a file that does not exist yet.
  ++ lib.optional (config.lab.proxy.enable && config.lab.proxy.tls.enable) (step {
    name = "cert-generate";
    kind = "cert-generate";
    retry = "idempotent";
    description = "Mint the lab CA and a wildcard certificate for '*.${config.lab.dns.zone}'";
    params = {
      inherit (config.lab.dns) zone;
    };
  })

  # The host services, and then the steps that depend on one being up.
  #
  # Order here is load-bearing rather than tidy. `registry-setup` reads the
  # live DNS container's address, so it cannot precede `setup-services`; and
  # both have to precede `create-cluster`, because `k3d cluster create` mounts
  # `registries.yaml` at creation time and k3s never reads it again.
  ++ lib.optional (config.lab.out.services != { }) (step {
    name = "setup-services";
    kind = "setup-services";
    retry = "idempotent";
    description = "Start lab infrastructure services";
  })

  ++ lib.optional config.lab.registry.enable (step {
    name = "registry-setup";
    kind = "registry-setup";
    retry = "idempotent";
    description = "Write registries.yaml + certs.d + lab-resolv.conf";
    params = {
      inherit (config.lab.registry) port;
      upstreams = map (u: u.host) config.lab.registry.upstreams;
      inherit (config.lab.dns) zone;
    };
  })

  ++ lib.optional (config.lab.registry.enable && config.lab.registry.warmCache) (step {
    name = "warm-cache";
    kind = "warm-cache";
    retry = "idempotent";
    description = "Pre-warm the lab registry with every declared image";
  })

  # Off unless asked for: it needs sudo and edits the host's resolver.
  ++ lib.optional (config.lab.dns.enable && config.lab.dns.configureHost) (step {
    name = "dns-setup";
    kind = "dns-setup";
    retry = "idempotent";
    description = "Point host DNS for '${config.lab.dns.zone}' at the lab resolver";
    params = {
      inherit (config.lab.dns.out.dnsInfo) host port zone;
    };
  })

  ++ lib.concatLists (
    lib.mapAttrsToList (name: c: [
      (step {
        name = "create-cluster-${name}";
        kind = "create-cluster";
        retry = "oneShot";
        description = "Create ${c.spec.provisioner} cluster '${name}'";
        cluster = name;
        params = {
          inherit name;
          inherit (c.spec) provisioner;
        };
      })
      (step {
        name = "deploy-manifests-${name}";
        kind = "deploy-manifests";
        retry = "idempotent";
        description = "Deploy manifests to '${name}'";
        cluster = name;
        params = {
          target = name;
          bootstrap = false;
          inherit (c.spec) kubeContext;
        };
      })
    ]) clusters
  );

  config.lab.out.teardownPlan =
    lib.mapAttrsToList (
      name: c:
      step {
        name = "destroy-cluster-${name}";
        kind = "destroy-cluster";
        retry = "destructive";
        description = "Destroy ${c.spec.provisioner} cluster '${name}'";
        cluster = name;
        params = {
          inherit name;
          inherit (c.spec) provisioner;
          skipIfMissing = true;
        };
      }
    ) clusters

    ++ lib.optional (config.lab.dns.enable && config.lab.dns.configureHost) (step {
      name = "dns-teardown";
      kind = "dns-teardown";
      retry = "idempotent";
      description = "Remove host DNS configuration for '${config.lab.dns.zone}'";
      params = {
        inherit (config.lab.dns) zone;
      };
    })

    # Services come down after the clusters and before the network they are
    # on, or `docker network rm` fails on a network still in use.
    ++ lib.optional (config.lab.out.services != { }) (step {
      name = "remove-services";
      kind = "remove-services";
      retry = "destructive";
      description = "Remove lab infrastructure services";
    })

    ++ [
      (step {
        name = "remove-network";
        kind = "remove-network";
        retry = "destructive";
        description = "Remove docker network '${config.lab.name}'";
      })
    ];
}
