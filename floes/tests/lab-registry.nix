# lab-registry, alone.
#
# The second host floe, and the first with plan steps of its own. Two things
# are worth pinning: the zot config, because a mirror zot does not consult is
# a cache that silently does nothing; and the steps, because they say *when*
# rather than *what* and the lab is what turns that into an anchor.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };

  # The list a lab writes. `lab.registry.upstreams` is where it lives for now,
  # so the floe has no default of its own and a test has to say one — which is
  # also what lets these cases name the two odd entries deliberately.
  upstreams = [
    {
      host = "codeberg.org";
      url = "https://codeberg.org";
      tlsVerify = true;
      prefixes = [ "forgejo/**" ];
    }
    {
      host = "ghcr.io";
      url = "https://ghcr.io";
      tlsVerify = true;
      prefixes = [ ];
    }
    {
      host = "docker.io";
      url = "https://registry-1.docker.io";
      tlsVerify = true;
      prefixes = [ ];
    }
  ];

  r = support.evalFloe {
    name = "lab-registry";
    stubValues.zone.zone = "example.test";
    inputs = { inherit upstreams; };
  };

  service = r.link.provides.lab-registry.service;
  steps = r.link.provides.lab-registry.step.steps;

  # The ports are the lab's allocated slot, not numbers chosen here: the floe
  # reads them off `lib/allocation.nix` from the lab name on `LAB_NETWORK`, so
  # a case naming a literal would be re-deriving the scheme.
  allocation = support.catallaxy.allocationFor "example";

  zot = builtins.fromJSON service.volumes."/etc/zot/config.json".content;
in
lib.runTests {

  # Every upstream the lab pulls from, in the order zot consults them. An
  # image whose host is not here goes to the public registry directly, which
  # works and defeats the cache — so the default list is the claim.
  testItMirrorsEveryUpstreamTheLabPullsFrom = {
    expr = map (u: lib.head u.urls) zot.extensions.sync.registries;
    expected = [
      "https://codeberg.org"
      "https://ghcr.io"
      "https://registry-1.docker.io"
    ];
  };

  # Docker Hub is the reason `host` and `url` are two inputs: containerd looks
  # a mirror up under `docker.io` and zot syncs from `registry-1.docker.io`.
  # The step is told the former and the config carries the latter.
  testTheMirrorNameAndTheSyncUrlAreBothCarried = {
    expr = {
      containerdLooksUp = lib.last steps.registry-setup.params.upstreams;
      zotSyncsFrom = lib.head (lib.last zot.extensions.sync.registries).urls;
    };
    expected = {
      containerdLooksUp = "docker.io";
      zotSyncsFrom = "https://registry-1.docker.io";
    };
  };

  # Prefixes where an upstream has them, absent where it does not. Without
  # them zot walks every configured upstream on each cold pull, ignoring
  # containerd's `?ns=` hint, which is most of cold-pull time.
  testAnUpstreamWithPrefixesNamesThem = {
    expr = {
      codeberg = map (c: c.prefix) (lib.head zot.extensions.sync.registries).content;
      ghcr = (lib.elemAt zot.extensions.sync.registries 1) ? content;
    };
    expected = {
      codeberg = [ "forgejo/**" ];
      ghcr = false;
    };
  };

  # Running is not answering, and `registry-setup` reads from it.
  testItWaitsUntilTheRegistryAnswers = {
    expr = {
      inherit (service.readyProbe) kind path expectedStatus;
      port = service.readyProbe.port;
    };
    expected = {
      kind = "http";
      path = "/v2/";
      expectedStatus = 200;
      port = allocation.registry;
    };
  };

  # A step says when, not what, and it is its own output kind: running a
  # container and contributing a step are two declarations. `beforeClusters` is
  # a condition the lab turns into one anchor per cluster, because a floe has
  # no name for a cluster it is not in — `k3d cluster create` mounts `registries.yaml` at creation and k3s
  # never reads it again, so "before any cluster" is the real constraint.
  testItsStepsSayWhenNotWhere = {
    expr = lib.mapAttrs (_: s: {
      inherit (s) beforeClusters;
      after = s.after or [ ];
    }) steps;
    expected = {
      registry-setup = {
        beforeClusters = "created";
        after = [
          "provides:lab/services"
          "optional:provides:lab/ingress-ca"
        ];
      };
      warm-cache = {
        beforeClusters = "created";
        after = [ "provides:lab/services" ];
      };
    };
  };

  # The warm is the one step a deployer turns off, because it trades startup
  # time for a slow first apply. Off, the step is not there at all.
  testWithoutWarmingThereIsNoWarmStep = {
    expr =
      lib.attrNames
        (support.evalFloe {
          name = "lab-registry";
          stubValues.zone.zone = "example.test";
          inputs = {
            warmCache = false;
            inherit upstreams;
          };
        }).link.provides.lab-registry.step.steps;
    expected = [ "registry-setup" ];
  };
}
