# What a lab's own floe is built with.
#
# Exactly what `mkClusterFloe` is one level down: the lab frame — the inputs
# every lab has and the policies every lab is held to — plus the units every
# lab holds, and the result is callable so `labs.minimal { }` instantiates it
# the way `clusters.app { }` does.
#
# An author declares the inputs *their* lab's environments may vary, so what
# can differ between `minimal.local` and `minimal.tls` is readable from the
# definition's header. That was five files and a module merge.
#
# The definition is built once. It was rebuilt per instantiation while
# `inclusion.defaults` was a plain attrset and the lab's had to be derived
# from units arriving as an input — so a second throwaway `mkFloe` existed
# only to resolve the inputs early. Both are gone: `defaults` takes the same
# argument `units` does, and a `singleton` provider needs no entry at all.
{
  lib,
  floe,
  sigs,
  floes,
  claimUnitFor,
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

  # What a lab writes about one cluster: the floe, and the claim that answers
  # the hole it leaves open.
  #
  # A plain record where it was a 189-line submodule whose other ten options
  # were `lowerCluster`'s results. Those are the lowering's to return, and a
  # submodule that holds two authored fields and eight computed ones reads as
  # though a deployer might set any of them.
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

          Its claim must be open. `requires.claim = sigs.KUBERNETES_CLUSTER`
          is what makes one cluster floe serve k3d here and Talos elsewhere,
          and `claim` below is what answers it.
        '';
      };

      claim = mkOption {
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

  # The inputs every lab has, whatever else its author declares.
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

  # A unit name a cluster already took.
  #
  # `//` is what joins the framework's units, the clusters', the author's and
  # the instantiation's, and a collision does not fail — it replaces. Whatever
  # the loser provided is then simply absent, and the symptom is an export that
  # resolved yesterday reading `attribute 'delivery' missing` somewhere in the
  # lowering, naming neither thing that collided.
  #
  # A throw and not a policy, because a policy runs on a link and this is about
  # what the link is built from: by the time one could look, one of the two is
  # already gone.
  refuseCollisions =
    labName: clusterNames: units:
    let
      taken = clusterNames ++ map claimUnitFor clusterNames;
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
              "the claim of cluster '${lib.removeSuffix "-claim" n}'"
          )
        ) collisions
        + ". Both are units of the lab's one link, so one replaces the other and whatever it "
        + "provided is simply gone. Rename the lab unit."
      );

  # The lab frame. `labInputs` above is the half an author reads; this is the
  # pair that gets applied.
  labFrame = {
    baseInputs = labInputs;
    policies = labPolicies;
  };

  # The definition without any instantiation, for the generated page: the
  # declared interface is what a reader needs and it does not depend on what a
  # lab was handed.
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

  # Everything about one lab that follows from its inputs: what it is called,
  # what it is allocated, where its clusters are placed, and the units that
  # places them.
  #
  # One function, because `units` and the facts the lowering is handed have to
  # be describing the same lab — the placements the link is built from are the
  # ones it then lowers.
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
          inherit (entry) floe claim;
        }
      ) (apply (args.clusters or { }) // given.clusters);

      clusterUnits =
        lib.mapAttrs (_: p: p.clusterFloe) placements
        // lib.mapAttrs' (n: p: lib.nameValuePair (claimUnitFor n) p.claim) placements;

      ownUnits = lib.filterAttrs (_: inst: inst != null) (
        frameworkUnits // apply (args.units or { }) // given.units
      );
    in
    {
      name = labName;
      inherit subnet placements;
      inherit (given) zone verifyEndpoints secretsEnvFile;

      units = clusterUnits // refuseCollisions labName (lib.attrNames placements) ownUnits;
    };

in
{
  # mkLabFloe :: mkFloe-args -> callable floe definition
  #
  #   labs.minimal = mkLabFloe {
  #     name = "minimal";
  #     summary = "One cluster, a platform, and one service behind it.";
  #     inputs.tls = lib.mkOption { type = lib.types.bool; default = false; };
  #     units = _: { registry = floes.lab-registry { }; };
  #     clusters = { inputs, ... }: { app = { floe = …; claim = …; }; };
  #   };
  #
  #   labs.minimal { name = "minimal.tls"; tls = true; }
  #
  # Callable, so an environment instantiates it the way `clusters.app { }`
  # instantiates a cluster floe, and an attrset, so the declared interface is
  # readable without instantiating anything.
  #
  # `units` and `clusters` may be functions of the checked inputs or plain
  # values. A lab's own are merged over the framework's, and over whatever the
  # instantiation passed through the `units` input — which is how a consumer
  # adds theirs.
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
