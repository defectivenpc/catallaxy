{
  description = "catallaxy: declarative Kubernetes platform management";

  # The platform is built on the floe interface, which lives in its
  # own repository and arrives as the `floes` input below.
  # Two earlier implementations preceded it; what they cost is recorded in
  # `docs/prior-implementations.md`, and the code is in git.
  #
  # `labs` and `labPackages` are the two attribute paths `cata` resolves. The
  # CLI is untouched and its contract is unchanged.

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    nix-kube-generators.url = "github:farcaller/nix-kube-generators";

    # The floe interface, extracted into its own repository. Local while the
    # port is in flight; this becomes a pinned `github:` input before it goes
    # anywhere, and that is the only line that changes.
    floes.url = "path:/home/whitehead/workspace/praxiotic/floes";

    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-kube-generators,
      floes,
      crane,
      rust-overlay,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # One `lib` reaches both, so floe's own nixpkgs pin decides nothing here.
      floeCore = floes.mkFloeLib lib;
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        treefmtEval = treefmt-nix.lib.evalModule pkgs (
          import ./nix/treefmt.nix { inherit lib rustToolchain; }
        );

        kubelib = nix-kube-generators.lib { inherit pkgs; };
        cataCharts = import ./lib/charts.nix { inherit lib pkgs kubelib; };
        k8sSpecs = import ./lib/k8s-specs.nix { inherit lib pkgs cataCharts; };

        # The CRD artifacts the types are generated from, which are the same
        # ones the floes install: each floe carrying a `crds.nix` names its
        # own. See `floes/crds.nix`.
        floeCrds = import ./floes/crds.nix { inherit lib; };
        crdSources = lib.mapAttrs (_: f: f { inherit cataCharts k8sSpecs; }) floeCrds.sources;

        # One derivation holding the whole generated tree, which the check
        # diffs against and `refresh-generated-types` copies out of — so the
        # committed tree and the check cannot be produced by two pipelines
        # that disagree.
        generatedTypes = import ./nix/generated-types.nix {
          inherit
            lib
            pkgs
            k8sSpecs
            crdSources
            ;
          inherit (packages') cata;
        };

        packages' = import ./pkgs {
          inherit
            lib
            pkgs
            craneLib
            rustToolchain
            ;

          # The step schema, from the module that accepts one. No lab in it:
          # a lab is a floe, so its reference is `nix/floe-docs.nix`'.
          optionsJSON = import ./nix/option-docs.nix { inherit lib pkgs; };
        };

        allocations = import ./nix/allocations.nix { inherit lib pkgs labDefs; };

        labs = import ./lib/lab.nix {
          inherit
            lib
            pkgs
            floeCore
            cataCharts
            k8sSpecs
            ;
          examplesPath = ./examples/labs;
        };

        # Fixture labs render and snapshot but never run, so they are in
        # `labPackages` and not in `labs`.
        exampleLabs = labs.discoverLabs;
        fixtureLabs = labs.discoverFixtures;
        labDefs = exampleLabs // fixtureLabs;

        # The labs `nix run .#e2e` stands up, by hand.
        #
        # A predicate used to decide this: eight derived reasons a lab might
        # not be runnable unattended, an `unstable` string for the one that
        # was mid-migration, and a check pinning the table the predicate
        # produced. All of it to answer a question with ten possible answers
        # that changes a few times a year.
        #
        # A name here is a claim that someone has seen the lab come up. Adding
        # one is a line, removing one is a line, and the diff says which.
        e2eLabs = [
          "crossplane.nop"
          "gitops.local"
          "homelab.dns"
          "homelab.local"
          "minimal.cilium"
          "minimal.local"
          "minimal.secrets"
          "minimal.talos"
          "minimal.tls"
        ];

        # And the ones that spend money, which `nix run .#e2e-cloud` stands up
        # when a human asks, each with what it needs in the environment before
        # it creates anything billable. Never in `nix flake check`.
        cloudE2eLabs = {
          "cloud" = [ "DIGITALOCEAN_TOKEN" ];
          "every-floe" = [ "DIGITALOCEAN_TOKEN" ];

          # Nothing: the account this reaches is the management cluster's, and
          # the credential is held by the Crossplane controller there.
          "provisions" = [ ];
        };

        # Same reason, for the document the CLI parses: the check diffs
        # against this and `refresh-cli-configs` copies out of it, so the
        # fixture and the check cannot be produced by two pipelines that
        # disagree.
        cliConfigs = import ./nix/cli-configs.nix { inherit lib pkgs labDefs; };

        # And for the floes themselves. One derivation holding every floe's
        # interface, which the check diffs against and `refresh-docs`
        # copies out of — so the fixture and the check cannot be produced by
        # two pipelines that disagree.
        floePages = import ./nix/floe-docs.nix {
          inherit
            lib
            pkgs
            labDefs
            cataCharts
            k8sSpecs
            ;
          catallaxy = import ./lib/floe-catallaxy { inherit lib pkgs floeCore; };
          # Flattened, the way `lib/lab.nix` flattens it: the three groups are
          # how the set is organised on disk, not a namespace anything spells.
          floeSet = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ./floes));
        };

        # And one page per signature. A floe declares the signatures it touches
        # and cannot name its peers, so "which floe answers this" is computed
        # here, off the whole set — which is the one thing no floe's own page
        # can say.
        signaturePages = import ./nix/signature-docs.nix {
          inherit
            lib
            pkgs
            cataCharts
            k8sSpecs
            ;
          catallaxy = import ./lib/floe-catallaxy { inherit lib pkgs floeCore; };
          floeSet = lib.foldl' lib.mergeAttrs { } (lib.attrValues (import ./floes));
        };

        # Clusters written with no lab around them, as `mkCluster`
        # evaluates them. One fixture today, which is the thing a lab used
        # to be the only way to write.
        standaloneClusters = lib.mapAttrs (
          name: path:
          labs.mkCluster (
            {
              inherit name;
            }
            // import path {
              inherit lib pkgs;
              inherit (labs) catallaxy floes;
            }
          )
        ) { minimal = ./examples/clusters/minimal.nix; };

        # The one renderer over both emitters. Nix says what each page is;
        # `cata-build docs pages` decides what it looks like.
        referencePages = import ./pkgs/reference-pages.nix {
          inherit
            lib
            pkgs
            floePages
            signaturePages
            ;
          inherit (packages') cata;
        };
      in
      {
        legacyPackages = {
          charts = cataCharts;

          # What `refresh-docs` copies out of and `option-docs` diffs.
          inherit (packages') optionDocs;

          # The address plan, written down.
          inherit allocations;

          # The three a consumer flake calls. None is a derivation, which is
          # why they are here rather than in `packages`.
          inherit (labs) mkLab mkCluster mkFloes;

          # The two the CLI resolves, and the only two.
          labs = lib.mapAttrs (_: l: l.cliConfig) exampleLabs;
          labPackages = lib.mapAttrs (_: l: l.package) labDefs;

          inherit standaloneClusters;

          # One artifact per cluster: its document and the tree the document
          # names, buildable on its own.
          #
          # `cata cluster up --from-file <doc>` acts on one of these with no
          # lab in the path, which is the test of whether a cluster is a
          # concept on its own: every field that leaks back to the lab is a
          # parse failure naming the field rather than something nobody sees.
          clusters = lib.mapAttrs (
            _: l:
            lib.mapAttrs (
              name: c:
              pkgs.runCommand "cluster-${name}" { } ''
                mkdir -p $out
                cp ${pkgs.writeText "cluster.json" (builtins.toJSON c.spec)} $out/cluster.json
                ln -s ${c.manifests} $out/manifests
              ''
            ) l.clusters
          ) labDefs;

          # The intermediate a cluster is lowered from, for reading by hand.
          clusterPictures = lib.mapAttrs (_: l: lib.mapAttrs (_: c: c.out) l.clusters) labDefs;

          # The lists the e2e runners read.
          inherit e2eLabs cloudE2eLabs;

          # What `refresh-digests` iterates and what the digest checks cover —
          # everything that renders, fixtures included.
          digestLabs = lib.attrNames labDefs;

          # One derivation holding `<lab>.json` for every lab, which both
          # `cliConfig-<lab>` and `refresh-cli-configs` read. Fixtures
          # included, for the same reason the digests include them: a fixture
          # exists to be rendered and checked, and a cluster descriptor is
          # exactly the thing a fixture is cheapest to pin.
          labCliConfigs = cliConfigs;

          # Every generated reference page, rendered: `floes/<name>.md` and
          # `signatures/<name>.md`. What `refresh-docs` copies out of and the
          # per-page checks diff against, so the committed tree and the check
          # cannot come from two pipelines that disagree.
          inherit referencePages;

          # What `refresh-generated-types` copies out of and the
          # `generated-types` check diffs.
          inherit generatedTypes;

          # Both plans per lab, for `cata lab plan --from-file`. A fixture is
          # not in `labs`, so the CLI cannot resolve one by name — and the
          # snapshot check compares fixtures too, so there has to be a way to
          # produce the same text for them.
          labPlans = lib.mapAttrs (_: l: {
            inherit (l) deploymentPlan teardownPlan;
          }) labDefs;
        };

        packages = {
          default = packages'.cataWrapped;
          cata = packages'.cataWrapped;
          cata-unwrapped = packages'.cata;

          inherit (packages')
            e2e
            e2e-all
            e2e-cloud
            cloud-reap
            refresh-digests
            refresh-cli-configs
            refresh-docs
            refresh-allocations
            refresh-generated-types
            refresh-plans
            talks
            docs
            ;
        };

        apps.default = {
          type = "app";
          program = "${packages'.cataWrapped}/bin/cata";
        };

        # `nix run .#e2e` with no argument prints the eligible set and why the
        # rest are not, which is the intended way to find out.
        apps.e2e = {
          type = "app";
          program = "${packages'.e2e}/bin/cata-e2e";
        };

        apps.e2e-all = {
          type = "app";
          program = "${packages'.e2e-all}/bin/cata-e2e-all";
        };

        # Spends money. Never in `nix flake check`, never on a PR.
        apps.e2e-cloud = {
          type = "app";
          program = "${packages'.e2e-cloud}/bin/cata-e2e-cloud";
        };

        apps.cloud-reap = {
          type = "app";
          program = "${packages'.cloud-reap}/bin/cata-cloud-reap";
        };

        apps.refresh-digests = {
          type = "app";
          program = "${packages'.refresh-digests}/bin/refresh-digests";
        };

        apps.refresh-cli-configs = {
          type = "app";
          program = "${packages'.refresh-cli-configs}/bin/refresh-cli-configs";
        };

        apps.refresh-docs = {
          type = "app";
          program = "${packages'.refresh-docs}/bin/refresh-docs";
        };

        apps.refresh-allocations = {
          type = "app";
          program = "${packages'.refresh-allocations}/bin/refresh-allocations";
        };

        apps.refresh-generated-types = {
          type = "app";
          program = "${packages'.refresh-generated-types}/bin/refresh-generated-types";
        };

        apps.refresh-plans = {
          type = "app";
          program = "${packages'.refresh-plans}/bin/refresh-plans";
        };

        devShells.default = import ./nix/devshell.nix {
          inherit pkgs rustToolchain;
          packages = packages';
        };

        formatter = treefmtEval.config.build.wrapper;

        checks = import ./nix/checks {
          inherit
            self
            lib
            pkgs
            floeCore
            cataCharts
            k8sSpecs
            treefmtEval
            ;
          packages = packages';
          inherit labDefs;

          # `labDefs` includes fixtures; `counts` wants the runnable set.
          inherit exampleLabs;

          # Clusters with no lab around them, read on their own by
          # `cluster-artifact-standalone-<name>`.
          inherit standaloneClusters;

          # A check that a *wrong* lab is refused has to build one, and only
          # `mkLab` can: nothing about a link is inspectable without
          # evaluating it. The distribution and the floe set come with it,
          # because building a lab means writing a floe definition.
          inherit (labs)
            mkLab
            mkFloes
            catallaxy
            floes
            ;
          inherit (packages') optionDocs;
          inherit allocations;
          inherit
            cliConfigs
            referencePages
            generatedTypes
            floeCrds
            ;
        };
      }
    )
    // {
      # `nix flake init -t github:defectivenpc/catallaxy#consumer` — the
      # scaffold `docs/book/src/start-here/your-own-lab.md` walks through.
      # System-independent, so it sits outside `eachDefaultSystem`.
      templates.consumer = {
        path = ./templates/consumer;
        description = "A lab in your own flake, with catallaxy as an input.";
      };
    };
}
