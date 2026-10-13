# A Zot pull-through cache in front of every registry the lab pulls from.
#
# The host half again, and the second service to move — but the first with
# plan steps of its own, which is the thing worth reading. A step reaches the
# plan through `lab.steps`, the channel the lab already had for steps it
# contributes itself, so this needed somewhere to put them rather than a new
# path.
#
# `beforeClusters` is a condition and not an anchor. A step here has to run
# before any cluster is created — `k3d cluster create` mounts `registries.yaml`
# at creation and k3s never reads it again — and a floe has no name for a
# cluster it is not in. So it says *when* and the lab expands it, which is the
# same trade `teardown = "before-cluster-destroy"` already makes on a
# component's steps, pointing the other way.
#
# No `enable`. A floe absent from the lab's units is simply not there.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens needs wants;
in

floe.mkFloe {
  name = "lab-registry";
  summary = "A Zot pull-through cache on the host, so a rebuilt lab pulls from disk.";

  # One per lab. Two caches in front of the same upstreams is not a state
  # worth being able to write, and a singleton's provider needs no naming — so
  # placing this *is* the whole decision, where it was `lab.registry.enable`
  # plus a `lab.defaults.OCI_MIRROR` the lab had to write beside it.
  singleton = true;

  inputs = {
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Host port the registry listens on.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one: an allocated port looks free in a table of
        registered names and may not be — the ranges contain 5353 (mDNS) and
        5355 (LLMNR), and a host already running something is a fact no
        allocation can see.
      '';
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/project-zot/zot-linux-amd64:v2.1.17";
      description = "Zot container image.";
    };

    warmCache = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pull every image the lab's manifests reference into the cache before
        any cluster is created.

        Without it the first apply triggers zot's on-demand sync while the
        kubelet's image-pull deadline and the applier's rollout timeout are
        already running, and a slow upstream shows up as a rollout failure
        rather than as a slow pull.

        The step reads `images.txt` from the lab package and asks zot for each
        entry, which is what makes zot fetch it. Set this false when iterating
        on an apply and the up-front warm is not worth the wait.
      '';
    };

    upstreams = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = ''
                Bare upstream registry hostname, no scheme. This is the name
                containerd looks a mirror up under, so it must match the
                prefix in image references exactly — `docker.io/foo/bar`,
                `codeberg.org/forgejo/forgejo`.
              '';
            };

            url = lib.mkOption {
              type = lib.types.str;
              description = ''
                The URL zot syncs from: scheme, host, and any path. For most
                registries this is just `https://<host>`; the oddity is Docker
                Hub, whose `docker.io` name resolves to
                `https://registry-1.docker.io`. Separate from `host` because
                the two are genuinely different strings for the same registry,
                and each side needs its own.
              '';
            };

            tlsVerify = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether zot validates the upstream's TLS certificate.";
            };

            prefixes = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "forgejo/**" ];
              description = ''
                Repository prefixes this upstream is responsible for. When set,
                zot's sync only consults it for repos matching one of them.

                Purely a latency concern, and a large one: without prefixes zot
                walks every configured upstream in declared order on each cold
                pull, ignoring containerd's `?ns=<host>` hint. Naming the
                prefixes of a single-tenant registry removes the dead-end
                iteration that dominates cold-pull time.
              '';
            };
          };
        }
      );

      default = [
        {
          host = "codeberg.org";
          url = "https://codeberg.org";
          prefixes = [ "forgejo/**" ];
        }
        {
          host = "registry.k8s.io";
          url = "https://registry.k8s.io";
        }
        {
          host = "ghcr.io";
          url = "https://ghcr.io";
        }
        {
          host = "quay.io";
          url = "https://quay.io";
        }
        {
          host = "docker.io";
          url = "https://registry-1.docker.io";
        }
        {
          host = "public.ecr.aws";
          url = "https://public.ecr.aws";
        }
        {
          host = "xpkg.upbound.io";
          url = "https://xpkg.upbound.io";
        }
        {
          host = "oci.external-secrets.io";
          url = "https://oci.external-secrets.io";
        }
      ];

      description = ''
        The registries zot mirrors, in the order it consults them.

        Every image the lab pulls has to be reachable through one of these: a
        reference whose host is not here goes to the public registry directly,
        which works and defeats the cache.
      '';
    };
  };

  # The zone, resolved rather than threaded. It was a `zone` string input in
  # four host floes at once while `lab-zone` answered it for every cluster —
  # so the lab read one option and wrote it into five instantiations, with
  # nothing checking that they agreed.
  requires.zone = sigs.DNS_ZONE;

  # And the network, for the lab's name — which is what this container is
  # named after and what decides the host port it publishes on.
  requires.network = sigs.LAB_NETWORK;

  # What a cluster node reaches this through. A provisioner that can mount a
  # containerd config declares a hole for it; one that cannot — talos takes
  # machine config — declares none, and that is the whole of how a lab says
  # its nodes do not mirror.
  #
  # `name` is this floe's unit name, which is also its state directory, so
  # whatever resolves this carries the directory rather than the CLI joining
  # a literal and probing for the files.
  provides.ociMirror = sigs.OCI_MIRROR;

  provides.service = sigs.HOST_SERVICE;
  provides.step = sigs.LAB_STEPS;

  body =
    {
      inputs,
      requires,
      floe,
      ...
    }:
    let
      containerName = catallaxy.hostContainerFor requires.network.name "registry";
      port =
        if inputs.port != null then
          inputs.port
        else
          (catallaxy.allocationFor requires.network.name).registry;
    in
    {
      provides.ociMirror = {
        name = floe.name;
        inherit port;
      };

      provides.service = {
        description = "Zot OCI registry (image cache)";
        container = containerName;
        inherit (inputs) image;

        command = [ ];
        ports = [ "${toString port}:5000" ];
        networks = [ ];
        dnsContainers = [ ];
        extraMounts = [ ];

        readyProbe = {
          kind = "http";
          host = "127.0.0.1";
          inherit port;
          path = "/v2/";
          expectedStatus = 200;
          timeout = "60s";
        };

        volumes = {
          "/etc/zot/config.json".content = builtins.toJSON {
            distSpecVersion = "1.1.0";

            storage = {
              rootDirectory = "/var/lib/zot";
              dedupe = true;
            };

            http = {
              address = "0.0.0.0";
              port = "5000";
              compat = [ "docker2s2" ];
            };

            extensions.sync = {
              enable = true;
              registries = map (
                u:
                {
                  urls = [ u.url ];
                  onDemand = true;
                  inherit (u) tlsVerify;
                }
                // lib.optionalAttrs (u.prefixes != [ ]) {
                  content = map (prefix: { inherit prefix; }) u.prefixes;
                }
              ) inputs.upstreams;
            };
          };

          "/var/lib/zot".persist = "data";
        };

      };

      provides.step.steps = {
        registry-setup = {
          kind = "registry-setup";
          description = "Write registries.yaml + certs.d + lab-resolv.conf";
          provides = [ planTokens.lab.registryConfig ];

          after = [
            (needs planTokens.lab.services)
            (wants planTokens.lab.ingressCa)
          ];

          beforeClusters = "created";

          params = {
            inherit port;
            inherit (requires.zone) zone;
            upstreams = map (u: u.host) inputs.upstreams;
          };
        };
      }
      // lib.optionalAttrs inputs.warmCache {
        warm-cache = {
          kind = "warm-cache";
          description = "Pre-warm the lab registry with every declared image";
          provides = [ planTokens.lab.warmCache ];
          after = [ (needs planTokens.lab.services) ];
          beforeClusters = "created";
        };
      };
    };
}
