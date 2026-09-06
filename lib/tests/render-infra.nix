# Stacks and what they render — RFC 0003 §§5, 6, 10.
#
# Most of the resources category is text: which stack a resource lands in,
# what the reference to another resource becomes, which remote states get
# declared, and what gets refused. All of that is checkable without a tool,
# a credential or a cloud account, which is the whole reason this file is
# where the coverage lives rather than in an e2e run.
{ lib }:

let
  infra = import ../render/infra.nix { inherit lib; };

  # A token as `floe.mkDeferred` produces one, written out: these tests are
  # about the renderer, and building a floe to get one would make a failure
  # here name the floe machinery instead.
  ref = unit: resource: output: {
    __deferred = true;
    source = unit;
    path = [
      resource
      output
    ];
    phase = "post-apply";
  };

  providers = {
    local = {
      source = "hashicorp/local";
      version = "2.5.2";
    };
    random = {
      source = "hashicorp/random";
      version = "3.6.3";
    };
  };

  # Two floes, three resources, two phases. `zone` and `token` are in one
  # unit but different phases, so they land in different stacks — which is
  # what makes the phase, not the unit, the thing that splits state.
  resources = {
    dns = {
      zone = {
        provider = "local";
        type = "local_file";
        inputs = {
          filename = "/tmp/zone";
          content = "z";
        };
        outputs = [ "id" ];
        phase = "before-clusters";
      };
      record = {
        provider = "local";
        type = "local_file";
        inputs = {
          filename = "/tmp/record";
          content = ref "dns" "zone" "id";
        };
        outputs = [ "id" ];
        phase = "after-clusters";
      };
    };

    creds = {
      secret = {
        provider = "random";
        type = "random_password";
        inputs = {
          length = 32;
          # Across units as well as across stacks.
          keepers.zone = ref "dns" "zone" "id";
        };
        outputs = [ "result" ];
        phase = "after-clusters";
      };
    };
  };

  stacks = infra.collectStacks {
    scope = "app";
    inherit resources;
    publications.creds.apiToken = {
      resource = "secret";
      output = "result";
      store = "runtime";
      key = "api/token";
    };
  };

  render =
    name:
    infra.renderStack {
      inherit name providers stacks;
      stack = stacks.${name};
      stateDir = "/state";
    };

  fails = expr: !(builtins.tryEval (builtins.deepSeq expr "evaluated")).success;

  # One resource, one bad reference, rendered — the shortest path to each
  # refusal without a second fixture per case.
  renderWith =
    inputs:
    let
      only = {
        u.r = {
          provider = "local";
          type = "local_file";
          inherit inputs;
          outputs = [ "id" ];
          phase = "before-clusters";
        };
      };
      s = infra.collectStacks {
        scope = "app";
        resources = only;
      };
    in
    infra.renderStack {
      name = "app-u-before-clusters";
      stack = s."app-u-before-clusters";
      stacks = s;
      inherit providers;
      stateDir = "/state";
    };
in
lib.runTests {

  # ---- stack identity ------------------------------------------------------

  # `(instantiation, phase)`. `dns` contributes to two stacks because its two
  # resources are in different phases; `creds` shares the later one's phase
  # and still gets its own, because the unit is half the key.
  testAStackIsAnInstantiationAndAPhase = {
    expr = lib.attrNames stacks;
    expected = [
      "app-creds-after-clusters"
      "app-dns-after-clusters"
      "app-dns-before-clusters"
    ];
  };

  testResourcesLandInTheStackTheirPhaseNames = {
    expr = lib.mapAttrs (_: s: lib.attrNames s.resources) stacks;
    expected = {
      "app-creds-after-clusters" = [ "secret" ];
      "app-dns-after-clusters" = [ "record" ];
      "app-dns-before-clusters" = [ "zone" ];
    };
  };

  # ---- references ----------------------------------------------------------

  # Within one stack a reference is direct interpolation; across stacks it
  # becomes a remote-state read. Nothing declares which — it follows from
  # where the two resources ended up.
  testACrossStackReferenceBecomesRemoteState = {
    expr = (render "app-dns-after-clusters").resource.local_file.record.content;
    expected = "\${data.terraform_remote_state.app-dns-before-clusters.outputs.zone_id}";
  };

  # And the remote state is configured from where the producer's state
  # actually is. Two descriptions of one path disagree; there is one here.
  testRemoteStateIsConfiguredFromTheProducersBackend = {
    expr = (render "app-dns-after-clusters").data.terraform_remote_state;
    expected = {
      app-dns-before-clusters = {
        backend = "local";
        config.path = "/state/app-dns-before-clusters/terraform.tfstate";
      };
    };
  };

  # A stack that reads nothing declares no remote states at all, rather than
  # an empty block the tool would still have to be handed.
  testAStackThatReadsNothingDeclaresNoRemoteState = {
    expr = (render "app-dns-before-clusters") ? data;
    expected = false;
  };

  # References are found wherever they sit, not only at the top level.
  testAReferenceNestedInsideAnInputIsFound = {
    expr = (render "app-creds-after-clusters").resource.random_password.secret.keepers.zone;
    expected = "\${data.terraform_remote_state.app-dns-before-clusters.outputs.zone_id}";
  };

  # ---- ordering ------------------------------------------------------------

  # Derived from the references in both directions: apply order from the
  # references themselves, destroy order from their reverse. Neither is
  # declared, so neither can be forgotten.
  testOrderingIsDerivedFromReferences = {
    expr = lib.genAttrs (lib.attrNames stacks) (infra.dependenciesOf stacks);
    expected = {
      "app-creds-after-clusters" = [ "app-dns-before-clusters" ];
      "app-dns-after-clusters" = [ "app-dns-before-clusters" ];
      "app-dns-before-clusters" = [ ];
    };
  };

  # ---- outputs -------------------------------------------------------------

  # One output per declared attribute, whether or not anything reads it:
  # `tofu output -json` is how a publication gets a value, and it can only
  # return what the stack declares.
  # Sensitive uniformly: the block is a machine interface for the apply step
  # to read values out of, not a report, and a provider that marks its own
  # attribute sensitive refuses to have it re-exported unmarked.
  testEveryDeclaredOutputIsRendered = {
    expr = (render "app-dns-before-clusters").output;
    expected = {
      zone_id = {
        value = "\${local_file.zone.id}";
        sensitive = true;
      };
    };
  };

  # ---- publications --------------------------------------------------------

  # A publication names a resource and the stack follows from that resource's
  # phase. Declaring the phase on the publication too would be a second copy
  # of one fact, and the two could disagree.
  testAPublicationFollowsItsResourcesStack = {
    expr = map (p: p.key) stacks."app-creds-after-clusters".publications;
    expected = [ "api/token" ];
  };

  testAPublicationDoesNotLeakIntoAnotherStack = {
    expr = map (_: "x") stacks."app-dns-before-clusters".publications;
    expected = [ ];
  };

  # ---- refusals ------------------------------------------------------------
  #
  # Each names the resource and the output rather than the stack, because the
  # stack name is derived and a reader would have to work backwards from it.

  testTheControlRendersCleanly = {
    expr = fails (renderWith {
      filename = "/tmp/x";
      content = "c";
    });
    expected = false;
  };

  testAReferenceToAnUnknownResourceIsRefused = {
    expr = fails (renderWith {
      content = ref "u" "nosuch" "id";
    });
    expected = true;
  };

  # Outputs are declared, never inferred. Without that this is a reference to
  # nothing, discovered mid-apply, after things have been created.
  testAReferenceToAnUndeclaredOutputIsRefused =
    let
      two = {
        a.zone = {
          provider = "local";
          type = "local_file";
          inputs.content = "z";
          outputs = [ "id" ];
          phase = "before-clusters";
        };
        b.entry = {
          provider = "local";
          type = "local_file";
          inputs.content = ref "a" "zone" "arn";
          outputs = [ "id" ];
          phase = "after-clusters";
        };
      };
      s = infra.collectStacks {
        scope = "app";
        resources = two;
      };
    in
    {
      expr = fails (
        infra.renderStack {
          name = "app-b-after-clusters";
          stack = s."app-b-after-clusters";
          stacks = s;
          inherit providers;
          stateDir = "/state";
        }
      );
      expected = true;
    };

  testAReferenceNamingOneHalfOfAPathIsRefused = {
    expr = fails (renderWith {
      content = {
        __deferred = true;
        source = "u";
        path = [ "zone" ];
        phase = "post-apply";
      };
    });
    expected = true;
  };

  # A provider version the lab pins nowhere would otherwise be resolved from
  # the network at `init`, which is the one thing a pinned lab must not do.
  testAnUnpinnedProviderIsRefused =
    let
      s = infra.collectStacks {
        scope = "app";
        resources.u.r = {
          provider = "cloudflare";
          type = "cloudflare_zone";
          inputs.zone = "example.com";
          outputs = [ "id" ];
          phase = "before-clusters";
        };
      };
    in
    {
      expr = fails (
        infra.renderStack {
          name = "app-u-before-clusters";
          stack = s."app-u-before-clusters";
          stacks = s;
          inherit providers;
          stateDir = "/state";
        }
      );
      expected = true;
    };

  # ---- providers -----------------------------------------------------------

  # Only what the stack uses. A stack carrying every provider the lab pins
  # would make `init` download them all, and a lab's provider set grows.
  testOnlyTheProvidersAStackUsesAreRequired = {
    expr = (render "app-creds-after-clusters").terraform.required_providers;
    expected = {
      random = {
        source = "hashicorp/random";
        version = "3.6.3";
      };
    };
  };
}
