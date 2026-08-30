# The lab's pull-through image cache.
#
# A Zot registry on the host, in front of every upstream the lab pulls from.
# `registry-setup` writes a `registries.yaml` naming it as the mirror for each
# upstream, and `k3d cluster create` mounts that into every node, so a pull
# that would have gone to the internet goes here and is served from disk the
# second time.
#
# The cluster side of this is entirely CLI-driven and needs nothing from Nix:
# `cli/src/host/registry.rs` writes the files, `cli/src/io/k3d.rs` mounts them.
# What is here is the service to point them at.
{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;

  cfg = config.lab.registry;

  upstreamType = types.submodule {
    options = {
      host = mkOption {
        type = types.str;
        description = ''
          Bare upstream registry hostname, no scheme. This is the name
          containerd looks a mirror up under, so it must match the prefix in
          image references exactly — `docker.io/foo/bar`,
          `codeberg.org/forgejo/forgejo`.
        '';
      };

      url = mkOption {
        type = types.str;
        description = ''
          The URL zot syncs from: scheme, host, and any path. For most
          registries this is just `https://<host>`; the oddity is Docker Hub,
          whose `docker.io` name resolves to `https://registry-1.docker.io`.

          Separate from `host` because the two are genuinely different
          strings for the same registry, and each side needs its own.
        '';
      };

      tlsVerify = mkOption {
        type = types.bool;
        default = true;
        description = "Whether zot validates the upstream's TLS certificate.";
      };

      prefixes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "forgejo/**" ];
        description = ''
          Repository prefixes this upstream is responsible for. When set,
          zot's sync only consults it for repos matching one of them.

          Purely a latency concern, and a large one: without prefixes zot
          walks every configured upstream in declared order on each cold
          pull, ignoring containerd's `?ns=<host>` hint. Naming the prefixes
          of a single-tenant registry removes the dead-end iteration that
          dominates cold-pull time.
        '';
      };
    };
  };

  zotConfig = builtins.toJSON {
    distSpecVersion = "1.1.0";
    storage = {
      rootDirectory = "/var/lib/zot";
      dedupe = true;
    };
    http = {
      address = "0.0.0.0";
      port = "5000";

      # containerd still asks for Docker schema-2 manifests, which zot does
      # not serve without being told to.
      compat = [ "docker2s2" ];
    };
    extensions.sync = {
      enable = true;
      registries = map (
        u:
        {
          urls = [ u.url ];

          # What makes this a pull-through cache rather than a scheduled
          # mirror: nothing is fetched until something asks for it.
          onDemand = true;
          inherit (u) tlsVerify;
        }
        // lib.optionalAttrs (u.prefixes != [ ]) {
          content = map (p: { prefix = p; }) u.prefixes;
        }
      ) cfg.upstreams;
    };
  };
in
{
  options.lab.registry = {
    enable = mkEnableOption "a Zot pull-through cache in front of the registries this lab pulls from";

    port = mkOption {
      type = types.port;
      default = 5050;
      description = "Host port the registry listens on.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/project-zot/zot-linux-amd64:v2.1.17";
      description = "Zot container image.";
    };

    containerName = mkOption {
      type = types.str;
      default = "catallaxy-${config.lab.name}-registry";
      defaultText = lib.literalExpression ''"catallaxy-''${config.lab.name}-registry"'';
      description = "Docker container name, which is also how a running lab's registry is identified.";
    };

    warmCache = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Pull every image the lab's manifests reference into the cache before
        any cluster is created.

        Without it the first apply triggers zot's on-demand sync while the
        kubelet's image-pull deadline and the applier's rollout timeout are
        already running, and a slow upstream shows up as a rollout failure
        rather than as a slow pull.

        The step reads `images.txt` from the lab package and asks zot for
        each entry, which is what makes zot fetch it. Set this false when
        iterating on an apply and the up-front warm is not worth the wait.
      '';
    };

    upstreams = mkOption {
      type = types.listOf upstreamType;
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
          host = "oci.external-secrets.io";
          url = "https://oci.external-secrets.io";
        }
      ];
      description = ''
        The registries the cache sits in front of. Each entry becomes both a
        zot sync source and a `mirrors:` entry in the `registries.yaml` every
        node mounts.

        Add one when a floe pulls from an upstream not listed here. Missing
        the entry, containerd goes to the public registry directly and has to
        resolve its name itself — which a lab node cannot do once the lab
        runs its own DNS: that server is authoritative for the zone and
        answers REFUSED for everything else, which a resolver treats as an
        answer rather than a reason to ask elsewhere. The pull then fails on
        a name that resolves perfectly well from the host.
      '';
    };

    service = mkOption {
      type = types.attrs;
      readOnly = true;
      description = "The `HostService` record `setup-services` starts.";
    };
  };

  config.lab.registry = mkIf cfg.enable {
    service = {
      description = "Zot OCI registry (image cache)";
      container = cfg.containerName;
      inherit (cfg) image;
      ports = [ "${toString cfg.port}:5000" ];

      # Not optional in practice. `container_running` is true between a
      # crash-looper's attempts, and without a probe nothing asks the service
      # anything — so `warm-cache` would run against a zot that has not opened
      # its socket and report every image as failed, non-fatally.
      readyProbe = {
        kind = "http";
        host = "127.0.0.1";
        port = cfg.port;
        path = "/v2/";
        expectedStatus = 200;
        timeout = "60s";
      };

      volumes = {
        "/etc/zot/config.json".content = zotConfig;

        # `persist`, not `content`: this is the branch of `prepare_volumes`
        # (`cli/src/host/services.rs:84`) that creates the directory and
        # chmods it 0777, which zot needs because it runs as its own
        # non-root uid. It is also what survives `lab destroy`, and so what
        # makes the next `lab up` not re-download several gigabytes.
        "/var/lib/zot".persist = "data";
      };
    };
  };
}
