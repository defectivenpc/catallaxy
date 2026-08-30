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
in
{
  config.lab.steps = {
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

  // {
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
        after = [ (needs t.lab.network) ];
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
