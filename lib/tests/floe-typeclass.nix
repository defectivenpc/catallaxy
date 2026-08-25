# Phase 0 of the floe-typeclass spike: does the mechanism work at all?
#
# Synthetic floes, not real ones. The point is to pin the four claims the
# design rests on before any of the 29 shipped floes is touched, so that if
# one of them is false it is false cheaply.
{ lib }:

let
  registry = import ../floe/registry.nix {
    inherit lib;
    modulesPath = ../../modules;
  };

  labStub = {
    name = "t";
    images = { };
  };

  evalWith =
    floeModules:
    lib.evalModules {
      modules = [
        (registry.mkRegistryModule {
          args.lab = labStub;
          extensions = [ registry.clusterExtension ];
        })
        { inherit floeModules; }
      ];
    };

  # A producer and a consumer, so `peers` is exercised in both directions.
  # Each declares the exports it publishes, extending the interface's empty
  # `exports` submodule — the same way the shipped floes do today, but at the
  # floe's own path rather than at `options.floes.<name>.exports`.
  producer =
    { lib, ... }:
    {
      options.exports = lib.mkOption {
        type = lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            port = lib.mkOption {
              type = lib.types.int;
              default = 0;
            };
          };
        };
      };
      config = {
        enable = true;
        namespace = "producer-ns";
        exports = {
          url = "http://producer.producer-ns.svc";
          port = 8080;
        };
      };
    };

  consumer =
    { lib, peers, ... }:
    {
      options.exports = lib.mkOption {
        type = lib.types.submodule {
          options.upstream = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
      };
      config = {
        enable = true;
        exports.upstream = peers.producer.url;
      };
    };

  evaluated = evalWith {
    producer = producer;
    consumer = consumer;
  };

  floes = evaluated.config.floes;

  # What a floe can see of a sibling. Asserted positively rather than by
  # catching the failure, for two reasons: `builtins.tryEval` catches `throw`
  # and `assert` but *not* "attribute missing", so the negative form cannot be
  # written; and the positive form is the stronger claim anyway — not "this
  # one trespass fails" but "the whole private surface is absent".
  #
  # Under the old shape a floe reached `config.floes.producer.namespace` and it
  # evaluated fine, which is exactly why the boundary needed a regex over
  # source text to catch it.
  visibleToAPeer =
    (evalWith {
      producer = producer;
      observer =
        { peers, ... }:
        {
          options.exports = lib.mkOption {
            type = lib.types.submodule {
              options.seen = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            };
          };
          config.exports.seen = lib.attrNames peers.producer;
        };
    }).config.floes.observer.exports.seen;

  # A plain NixOS module assigned into a floe slot. Should be refused by the
  # class check with a message naming the class, not by a pile of "option does
  # not exist" errors from inside the merge.
  wrongClass = builtins.tryEval (
    builtins.deepSeq
      (evalWith {
        impostor =
          { ... }:
          {
            _class = "nixos";
            config = { };
          };
      }).config.floes.impostor.enable
      "evaluated"
  );

  # Laziness: naming one peer must not force every floe's exports. `broken`
  # would throw if evaluated, so this passes only if reading producer's url
  # leaves it alone.
  lazyPeers = builtins.tryEval (
    builtins.deepSeq
      (evalWith {
        producer = producer;
        consumer = consumer;
        broken = { ... }: { config.exports = throw "this floe's exports were forced"; };
      }).config.floes.consumer.exports.upstream
      "evaluated"
  );
in
lib.runTests {

  # The interface is declared once and every instance has it, rather than each
  # floe declaring its own copy at `options.floes.<name>`.
  testEveryInstanceCarriesTheInterface = {
    expr = lib.all (n: floes.${n} ? bundles && floes.${n} ? steps && floes.${n} ? exports) [
      "producer"
      "consumer"
    ];
    expected = true;
  };

  # A floe's config is its own: it wrote `namespace`, not `floes.producer.namespace`.
  testAFloesConfigIsItsOwn = {
    expr = floes.producer.namespace;
    expected = "producer-ns";
  };

  # `namespace` defaults to the attribute name, which is what says the registry
  # key really is the floe's name.
  testNamespaceDefaultsToTheRegistryKey = {
    expr = floes.consumer.namespace;
    expected = "consumer";
  };

  # The headline: peers is real, and carries exports.
  testPeersCarriesASiblingsExports = {
    expr = floes.consumer.exports.upstream;
    expected = "http://producer.producer-ns.svc";
  };

  # And carries *only* exports — no `namespace`, no `bundles`, no `enable`.
  # This is the structural replacement for lib/floe-checks/boundary.nix's
  # regex over source text.
  testPeersCarriesNothingButExports = {
    expr = visibleToAPeer;
    expected = [
      "port"
      "url"
    ];
  };

  # The nominal type does something.
  testAWrongClassModuleIsRefused = {
    expr = wrongClass.success;
    expected = false;
  };

  # Reading one peer does not force the others.
  testPeersAreLazy = {
    expr = lazyPeers.success;
    expected = true;
  };

  # The registry is a config value, so the floe set is whatever config says.
  testTheRegistryIsConfig = {
    expr = lib.attrNames floes;
    expected = [
      "consumer"
      "producer"
    ];
  };
}
