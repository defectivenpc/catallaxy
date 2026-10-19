{ lib }:

let
  infra = import ../render/infra.nix { inherit lib; };

  ref = unit: resource: output: {
    __deferred = true;
    source = unit;
    retrieval = "catallaxy.resourceOutput";
    ref = {
      inherit resource output;
    };
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

  testACrossStackReferenceBecomesRemoteState = {
    expr = (render "app-dns-after-clusters").resource.local_file.record.content;
    expected = "\${data.terraform_remote_state.app-dns-before-clusters.outputs.zone_id}";
  };

  testRemoteStateIsConfiguredFromTheProducersBackend = {
    expr = (render "app-dns-after-clusters").data.terraform_remote_state;
    expected = {
      app-dns-before-clusters = {
        backend = "local";
        config.path = "/state/app-dns-before-clusters/terraform.tfstate";
      };
    };
  };

  testAStackThatReadsNothingDeclaresNoRemoteState = {
    expr = (render "app-dns-before-clusters") ? data;
    expected = false;
  };

  testAReferenceNestedInsideAnInputIsFound = {
    expr = (render "app-creds-after-clusters").resource.random_password.secret.keepers.zone;
    expected = "\${data.terraform_remote_state.app-dns-before-clusters.outputs.zone_id}";
  };

  testOrderingIsDerivedFromReferences = {
    expr = lib.genAttrs (lib.attrNames stacks) (infra.dependenciesOf stacks);
    expected = {
      "app-creds-after-clusters" = [ "app-dns-before-clusters" ];
      "app-dns-after-clusters" = [ "app-dns-before-clusters" ];
      "app-dns-before-clusters" = [ ];
    };
  };

  testEveryDeclaredOutputIsRendered = {
    expr = (render "app-dns-before-clusters").output;
    expected = {
      zone_id = {
        value = "\${local_file.zone.id}";
        sensitive = true;
      };
    };
  };

  testAPublicationFollowsItsResourcesStack = {
    expr = map (p: p.key) stacks."app-creds-after-clusters".publications;
    expected = [ "api/token" ];
  };

  testAPublicationDoesNotLeakIntoAnotherStack = {
    expr = map (_: "x") stacks."app-dns-before-clusters".publications;
    expected = [ ];
  };

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
        retrieval = "catallaxy.resourceOutput";
        ref = {
          resource = "zone";
          output = "id";
        };
      };
    });
    expected = true;
  };

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
