{
  lib,
  floe,
  sigs,
  floes,
  provisionerUnitFor,
  labPolicies,
  allocationFor,
  placeCluster,
}:

let
  inherit (lib) mkOption types;
  inherit (import ./frame.nix { inherit lib floe; }) framedArgs;

  floeInstance = types.raw // {
    name = "floeInstance";
    description = "an instantiated floe";
    check = v: v ? __floeInstance;
  };

  clusterEntry = types.submodule {
    options = {
      floe = mkOption {
        type = floeInstance;
        description = ''
          This cluster, as a floe whose units are the components in it.

          Authored, not assembled: the floe declares what it needs of
          whatever places it, what it offers back, and which of its units each
          offer comes from — so its interface is readable from its header
          without evaluating anything.

          Its cluster hole must be open. `requires.cluster = sigs.KUBERNETES_CLUSTER`
          is what makes one cluster floe serve k3d here and Talos elsewhere,
          and `claim` below is what answers it.
        '';
      };

      provisioner = mkOption {
        type = floeInstance;
        example = lib.literalExpression "floes.k3d-cluster { }";
        description = ''
          What brings this cluster into existence, as a floe providing
          `KUBERNETES_CLUSTER`.

          Beside the cluster rather than inside it, and that is the whole
          point: an environment swaps the provisioner without touching a
          component, because the components resolve against the hole this
          fills rather than against the thing that fills it.

          `name`, `instanceName` and `network` are filled in from the
          cluster's own name and the lab's, since a floe is instantiated
          before it is placed and cannot read the cluster it provisions.
        '';
      };
    };
  };

  labInputs = {
    name = mkOption {
      type = types.str;
      description = ''
        Unique name for the lab. Also the docker network name, the prefix on
        every container, and what every host port and the subnet are allocated
        from — so two labs on one host do not collide.
      '';
    };

    zone = mkOption {
      type = types.str;
      description = ''
        Domain the lab's hostnames hang off, handed to every floe that needs it
        through `DNS_ZONE`.

        A lab identity fact, like `name`: it is what routes are declared under
        and what `registry-setup` names the in-cluster registry at, whether or
        not the lab runs a server that answers for it. Placing `floes.lab-dns`
        is what adds one.
      '';
    };

    zonePort = mkOption {
      type = types.nullOr types.port;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Port the zone's server answers on: what `lab-dns` publishes and what a
        pod forwards to.

        Null takes the lab's allocated slot, which is every lab in this tree.
        Set it to move off one: the DNS range spans 5300-5555, which contains
        5353 (mDNS) and 5355 (LLMNR, held by systemd-resolved on most Linux
        hosts), so two names in 256 land on a port that looks free and is not.
      '';
    };

    subnet = mkOption {
      type = types.nullOr types.str;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        Docker network the lab's containers share, in CIDR form. `cata lab up`
        parses this before it runs anything, to refuse a lab whose subnet
        overlaps one already on the host.

        Resolved by the lab and not by `lab-network`, unlike the host ports:
        three lab-level readers need the answer — `cliConfig`, and the two
        checks that refuse two labs whose ranges overlap — and a `provides`
        does not leave the lab's link.
      '';
    };

    units = mkOption {
      type = types.attrsOf (types.nullOr floeInstance);
      default = { };
      example = lib.literalExpression "{ proxy = floes.lab-proxy { }; }";
      description = ''
        Floes that are units of the lab's own link rather than of a cluster's.

        Two kinds, and the link does not distinguish them. One answers a
        signature every cluster can resolve, which is how a fact the lab holds
        reaches the floes that need it. The other provides a `HOST_SERVICE` — a
        container the lab runs on the operator's machine — which `lab-services`
        collects. A host floe's *name* here is a CLI contract rather than a
        label, because that collection is keyed by it and
        `cli/src/host/state.rs` keys state directories by the same name.

        This is also where a consumer adds their own: anything instantiated
        from their own floe set is a unit like any other.

        `null` withdraws one, which is what an environment writes to drop a
        floe its base lab placed. Placing a floe is the whole of saying a lab
        runs it, so there is no `enable` to turn off.
      '';
    };

    clusters = mkOption {
      type = types.attrsOf clusterEntry;
      default = { };
      description = ''
        The clusters this lab builds, each an authored floe and the claim that
        answers it.
      '';
    };

    defaults = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        CLUSTER_PROVISIONING = "mgmt";
      };
      description = ''
        Which cluster an *optional* hole means, at lab scope, by signature
        name.

        An optional hole is never wired by a provider merely being present, so
        a lab holding a cluster that provisions others is not thereby a lab
        where every external cluster is provisioned by it. That is a third
        decision, and this is where it is made.

        A `singleton` floe needs no entry: the linker already refuses a second
        of one, so "which one" has exactly one answer and the lab fills it in.
      '';
    };

    images = mkOption {
      type = types.submodule {
        options = {
          requireDigest = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Refuse any image this lab renders without a `sha256:` digest.

              Off by default, and enforced by the `image-pin` lint rule rather
              than at apply time: you find out in CI and not during a rollout.
              A tag is a mutable pointer, so a lab that passed yesterday can
              apply something else today and nothing in the rendered output
              changes to say so.
            '';
          };

          allowedRegistries = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = [
              "ghcr.io"
              "registry.k8s.io"
            ];
            description = ''
              Registries this lab's images may come from. Empty permits any.

              A warning rather than an error, because a chart's default image
              is somebody else's decision and finding out is the first step.
              What it catches is a floe quietly adding a dependency on a
              registry an airgap has no mirror for.
            '';
          };
        };
      };
      default = { };
      description = "What the `image-pin` lint rule holds this lab's images to.";
    };

    secretsEnvFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "examples/labs/gitops/envs/ci.env";
      description = ''
        A file a runner sources before the lab starts, for `env`-backed stores.

        A repository-relative path rather than a Nix path: a Nix path resolves
        into the store, which under lazy trees names something never written to
        disk, so the runner is handed a path that does not exist. The relative
        form is also what a human can act on — it is the argument to `git add`.

        Catallaxy never reads it. The environment is the interface; this only
        names one way to fill it.
      '';
    };

    verifyEndpoints = mkOption {
      type = types.submodule {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Probe every publicly routed hostname the clusters expose.

              The hosts and the paths come from `cluster.out.exposedHosts`,
              which the elaborator reads off the rendered routes, so this needs
              no list to maintain.
            '';
          };

          acceptStatuses = mkOption {
            type = types.listOf (types.ints.between 100 599);
            default = [ ];
            example = [
              401
              403
            ];
            description = ''
              Extra HTTP statuses that count as the endpoint answering.

              A gateway that routes to a workload demanding auth answers 401,
              and that proves the route works. 404 is deliberately not listable
              here: it is what a gateway returns when it has *no* route, which
              is the failure this check exists to catch.
            '';
          };
        };
      };
      default = { };
      description = "What `cata lab verify` probes once the lab is up.";
    };
  };

  refuseCollisions =
    labName: clusterNames: units:
    let
      taken = clusterNames ++ map provisionerUnitFor clusterNames;
      collisions = lib.filter (n: lib.elem n taken) (lib.attrNames units);
    in
    if collisions == [ ] then
      units
    else
      throw (
        "lab '${labName}': "
        + lib.concatMapStringsSep "; " (
          n:
          "the unit '${n}' collides with "
          + (
            if lib.elem n clusterNames then
              "the cluster of the same name"
            else
              "the claim of cluster '${lib.removeSuffix "-provisioner" n}'"
          )
        ) collisions
        + ". Both are units of the lab's one link, so one replaces the other and whatever it "
        + "provided is simply gone. Rename the lab unit."
      );

  labFrame = {
    baseInputs = labInputs;
    policies = labPolicies;
  };

  labFloeInterface =
    args:
    floe.mkFloe (
      framedArgs labFrame (
        removeAttrs args [
          "clusters"
          "units"
        ]
      )
    );

  labOf =
    args: given:
    let
      labName = given.name;

      subnet = if given.subnet == null then (allocationFor labName).subnet else given.subnet;

      apply = f: if lib.isFunction f then f { inputs = given; } else f;

      frameworkUnits = {
        network = floes.lab-network {
          name = labName;
          inherit subnet;
        };

        zone = floes.lab-zone {
          inherit (given) zone;
          port = given.zonePort;
        };

        delivery = floes.lab-delivery { };
        services = floes.lab-services { };
        steps = floes.lab-steps { };
        secrets = floes.lab-secrets { };
      };

      placements = lib.mapAttrs (
        clusterName: entry:
        placeCluster {
          inherit clusterName labName;
          inherit (entry) floe provisioner;
        }
      ) (apply (args.clusters or { }) // given.clusters);

      clusterUnits =
        lib.mapAttrs (_: p: p.clusterFloe) placements
        // lib.mapAttrs' (n: p: lib.nameValuePair (provisionerUnitFor n) p.provisioner) placements;

      ownUnits = lib.filterAttrs (_: inst: inst != null) (
        frameworkUnits // apply (args.units or { }) // given.units
      );
    in
    {
      name = labName;
      inherit subnet placements;
      inherit (given)
        zone
        verifyEndpoints
        secretsEnvFile
        images
        ;

      units = clusterUnits // refuseCollisions labName (lib.attrNames placements) ownUnits;
    };

in
{
  mkLabFloe =
    args:
    let
      def = floe.mkFloe (
        framedArgs labFrame (removeAttrs args [ "clusters" ])
        // {
          units = { inputs, ... }: (labOf args inputs).units;
          defaults = { inputs, ... }: inputs.defaults;
        }
      );

      instantiate =
        supplied:
        let
          inst = def.instantiate supplied;
        in
        inst
        // {
          lab = removeAttrs (labOf args inst.inputsChecked) [ "units" ];
        };
    in
    labFloeInterface args
    // {
      inherit instantiate;
      __functor = _: instantiate;
    };
}
