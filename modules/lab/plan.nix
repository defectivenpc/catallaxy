# The steps the framework itself contributes.
#
# Declared, not ordered. Each one says what it publishes and what it waits on,
# and `modules/lab/planner` resolves that into a sequence — so a floe's step
# can insert itself between two of these without either knowing about it.
#
# The ordering facts here are the same ones the hand-written list carried, now
# written as conditions rather than as positions:
#
#   - `registry-setup` reads the live DNS container's address, so it cannot
#     precede `setup-services`;
#   - both must precede `create-cluster`, because `k3d cluster create` mounts
#     `registries.yaml` at creation and k3s never reads it again;
#   - `cert-generate` must precede `setup-services`, because the ingress
#     bind-mounts the certificate and a container cannot mount a file that is
#     not there yet.
{ config, lib, ... }:

let
  t = import ../../lib/plan-tokens.nix { inherit lib; };
  inherit (t) needs wants;

  clusters = config.lab.clusters;
  clusterNames = lib.attrNames clusters;

  hasServices = config.lab.out.services != { };
  hasSecrets = config.lab.secrets.managed != { };
  hasCa = config.lab.proxy.enable && config.lab.proxy.tls.enable;
  hasRegistry = config.lab.registry.enable;
  hasHostDns = config.lab.dns.enable && config.lab.dns.configureHost;

  # Which clusters sit on the lab's docker network.
  #
  # `provider` is the descriptor's own answer — `docker` for k3d and talos,
  # something else for a cluster made in a cloud — so this asks the cluster
  # rather than matching on provisioner names the lab would then have to be
  # taught one at a time.
  onDockerNetwork = name: clusters.${name}.spec.provider == "docker";

  # The network exists for the containers that join it: the lab's own
  # services, and any cluster the operator's machine runs. A lab of nothing
  # but cloud clusters would otherwise create a docker network nothing is on,
  # and it would sit in the plan looking like a step that means something.
  needsDockerNetwork = hasServices || lib.any onDockerNetwork clusterNames;

  # ---- provisioning stacks — RFC 0003 -------------------------------------

  infraLib = import ../../lib/render/infra.nix { inherit lib; };

  stacks = lib.foldl' lib.mergeAttrs { } (lib.mapAttrsToList (_: c: c.stacks) clusters);

  phaseOfStack = name: (lib.head (lib.attrValues stacks.${name}.resources)).phase;

  # A stack's plan waits on the applies it reads from — *its plan*, not its
  # apply, because rendering a plan needs the producer's recorded state.
  # Derived from the references, so nothing is declared and nothing can be
  # forgotten.
  stackDeps = name: infraLib.dependenciesOf stacks name;

  infraSteps = lib.foldl' lib.mergeAttrs { } (
    lib.mapAttrsToList (
      stackName: _:
      let
        phase = phaseOfStack stackName;
        deps = stackDeps stackName;

        # Where this stack sits against the cluster lifecycle, stated in the
        # same detail in both directions. A single anchor covering every
        # phase leaves an `after-clusters` stack unordered against manifest
        # removal (RFC 0003 §6).
        againstClusters =
          if phase == "before-clusters" then map (n: (t.cluster n).created) clusterNames else [ ];

        afterClusters = lib.optionals (phase == "after-clusters") (
          map (n: needs (t.cluster n).created) clusterNames
        );
      in
      {
        "infra-plan-${stackName}" = {
          kind = "infra-plan";
          description = "Plan stack '${stackName}'";

          # A plan is read-only but it is not inert: it needs credentials and
          # it talks to a provider's API, so it must not run under a flag an
          # operator reads as "nothing will happen" (RFC 0003 §8).
          provides = [ "stack/${stackName}/planned" ];
          after = map (d: needs (t.stack d).applied) deps ++ afterClusters;
          before = map (a: wants a) againstClusters;
          params.stack = stackName;
        };

        "infra-apply-${stackName}" = {
          kind = "infra-apply";
          description = "Apply stack '${stackName}'";
          provides = [ (t.stack stackName).applied ];
          after = [ (needs "stack/${stackName}/planned") ];
          before = map (a: wants a) againstClusters;
          params.stack = stackName;
        };

        "infra-destroy-${stackName}" = {
          kind = "infra-destroy";
          description = "Destroy stack '${stackName}'";
          provides = [ (t.stack stackName).destroyed ];

          # Teardown reverses it: a stack is destroyed after everything that
          # reads from it, and after the clusters whose manifests may hold
          # what it published.
          after =
            map (d: wants (t.stack d).destroyed) (
              lib.filter (other: lib.elem stackName (stackDeps other)) (lib.attrNames stacks)
            )
            ++ map (n: wants (t.cluster n).destroyed) clusterNames;
          params.stack = stackName;
        };
      }
    ) stacks
  );
in
{
  config.lab.steps =
    lib.optionalAttrs needsDockerNetwork {
      docker-network-create = {
        kind = "docker-network-create";
        description = "Create docker network '${config.lab.name}'";
        provides = [ t.lab.network ];
        params = {
          name = config.lab.name;
          inherit (config.lab.network) subnet gateway;
        };
      };
    }

    # Before anything that could consume a value, and early enough that a lab
    # missing a secret fails in seconds rather than after a cluster exists.
    // lib.optionalAttrs hasSecrets {
      ensure-secrets = {
        kind = "ensure-secrets";
        description = "Check the lab's authored secret stores are readable";
        provides = [ t.lab.secrets ];

        # Every consumer, not just the services. A lab with no lab-level
        # services — which is most of the fixtures — leaves a lone `wants
        # services` resolving to nothing, and a step with no satisfied anchor
        # is unconstrained: the sort put this one *after* both clusters were
        # created and their manifests deployed, which is the failure the
        # comment above says the step exists to prevent.
        before = [
          (wants t.lab.services)
        ]
        ++ map (n: wants (t.cluster n).created) clusterNames;
        params.stores = lib.attrNames (
          lib.filterAttrs (_: s: s.direction == "authored") config.lab.secrets.stores
        );
      };
    }

    // lib.optionalAttrs hasCa {
      cert-generate = {
        kind = "cert-generate";
        description = "Mint the lab CA and a wildcard certificate for '*.${config.lab.dns.zone}'";
        provides = [ t.lab.ingressCa ];

        # The services bind-mount the certificate and `registry-setup` copies
        # the CA into each cluster's `certs.d`, so it precedes cluster creation
        # too — stated rather than left to arrive transitively through a
        # registry the lab may not have.
        before = [
          (wants t.lab.services)
        ]
        ++ map (n: wants (t.cluster n).created) clusterNames;
        params = {
          inherit (config.lab.dns) zone;
        };
      };
    }

    // lib.optionalAttrs hasServices {
      setup-services = {
        kind = "setup-services";
        description = "Start lab infrastructure services";
        provides = [ t.lab.services ];
        after = [ (needs t.lab.network) ];
      };

      remove-services = {
        kind = "remove-services";
        description = "Remove lab infrastructure services";
        provides = [ t.lab.servicesRemoved ];

        # After every cluster is gone, and before the network they were on:
        # `docker network rm` fails on a network still in use.
        after = map (n: wants (t.cluster n).destroyed) clusterNames;
        before = [ (wants t.lab.networkRemoved) ];
      };
    }

    // lib.optionalAttrs hasRegistry {
      registry-setup = {
        kind = "registry-setup";
        description = "Write registries.yaml + certs.d + lab-resolv.conf";
        provides = [ t.lab.registryConfig ];

        # Hard on services, because it reads the live DNS container's address;
        # soft on the CA, because a lab with TLS off has none to copy.
        after = [
          (needs t.lab.services)
          (wants t.lab.ingressCa)
        ];
        before = map (n: wants (t.cluster n).created) clusterNames;
        params = {
          inherit (config.lab.registry) port;
          upstreams = map (u: u.host) config.lab.registry.upstreams;
          inherit (config.lab.dns) zone;
        };
      };
    }

    // lib.optionalAttrs (hasRegistry && config.lab.registry.warmCache) {
      warm-cache = {
        kind = "warm-cache";
        description = "Pre-warm the lab registry with every declared image";
        provides = [ t.lab.warmCache ];
        after = [ (needs t.lab.services) ];
        before = map (n: wants (t.cluster n).created) clusterNames;
      };
    }

    // lib.optionalAttrs hasHostDns {
      dns-setup = {
        kind = "dns-setup";
        description = "Point host DNS for '${config.lab.dns.zone}' at the lab resolver";
        provides = [ t.lab.hostDns ];
        after = [ (wants t.lab.services) ];
        params = {
          inherit (config.lab.dns.out.dnsInfo) host port zone;
        };
      };

      dns-teardown = {
        kind = "dns-teardown";
        description = "Remove host DNS configuration for '${config.lab.dns.zone}'";
        provides = [ t.lab.hostDnsRemoved ];
        params = {
          inherit (config.lab.dns) zone;
        };
      };
    }

    // infraSteps

    // lib.optionalAttrs needsDockerNetwork {
      remove-network = {
        kind = "remove-network";
        description = "Remove docker network '${config.lab.name}'";
        provides = [ t.lab.networkRemoved ];
        after = map (n: wants (t.cluster n).destroyed) clusterNames;
      };
    }

    // lib.foldl' lib.mergeAttrs { } (
      lib.mapAttrsToList (name: c: {
        "create-cluster-${name}" = {
          kind = "create-cluster";
          description = "Create ${c.spec.provisioner} cluster '${name}'";
          cluster = name;
          provides = [ (t.cluster name).created ];

          # `needs`, not `wants`, so it is an error when the anchor is absent
          # rather than a step that floats. A cluster not on the lab's network
          # drops the edge entirely instead of needing something nothing makes.
          after = lib.optional (onDockerNetwork name) (needs t.lab.network);
          params = {
            inherit name;
            inherit (c.spec) provisioner;
          };
        };

        "deploy-manifests-${name}" = {
          kind = "deploy-manifests";
          description = "Deploy manifests to '${name}'";
          cluster = name;
          provides = [ (t.cluster name).deployed ];
          after = [ (needs (t.cluster name).created) ];
          params = {
            target = name;
            bootstrap = false;
            inherit (c.spec) kubeContext;
          };
        };

        "destroy-cluster-${name}" = {
          kind = "destroy-cluster";
          direction = "teardown";
          description = "Destroy ${c.spec.provisioner} cluster '${name}'";
          cluster = name;
          provides = [ (t.cluster name).destroyed ];
          params = {
            inherit name;
            inherit (c.spec) provisioner;
            skipIfMissing = true;
          };
        };
      }) clusters
    );
}
