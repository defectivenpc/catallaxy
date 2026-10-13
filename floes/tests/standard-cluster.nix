# standard-cluster, alone.
#
# What an inclusion asserts is not what a component asserts, so this suite
# checks different things from its neighbours: that the holes it leaves open
# are the ones it declares, that every export resolves and arrives sealed to
# the signature the boundary declared, that an inner unit's own provides stay
# inside, and that an inner unit's wiring is visible to whoever lowers the
# cluster.
#
# Its units are stood in for rather than real. A member defaults its own chart
# from `cataCharts`, which a suite deliberately has no access to — the harness
# passes `null` so that unit tests stay free of the chart pins — and forcing a
# real member would force that default. The assembly against the real members
# is what `homelab` renders; the contract is what this file holds.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  inherit (support) catallaxy stubs;
  inherit (catallaxy) floe sigs;

  # A stand-in member: provides what the real one provides, with the harness's
  # stub values, and declares the inputs the assembly passes it.
  member =
    {
      name,
      gives ? [ ],
      takes ? [ ],
      inputs ? { },
    }:
    floe.mkFloe {
      inherit name inputs;
      summary = "Fixture floe for a test suite.";
      requires = lib.listToAttrs (
        map (k: lib.nameValuePair stubs.${k}.sig.canonicalName stubs.${k}.sig) takes
      );
      provides = lib.listToAttrs (
        map (k: lib.nameValuePair stubs.${k}.sig.canonicalName stubs.${k}.sig) gives
      );
      body = _: {
        provides = lib.listToAttrs (
          map (k: lib.nameValuePair stubs.${k}.sig.canonicalName stubs.${k}.value) gives
        );
      };
    };

  callable = def: def // { __functor = _: def.instantiate; };

  members = lib.mapAttrs (_: m: callable (member m)) {
    gateway-api-crds = {
      name = "gateway-api-crds";
      gives = [ "gatewayApi" ];
      takes = [ "cluster" ];
    };

    cert-manager = {
      name = "cert-manager";
      gives = [
        "issuance"
        "webhook"
      ];
      takes = [ "cluster" ];
      inputs.rootFromLab = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Fixture input.";
      };
    };

    trust-manager = {
      name = "trust-manager";
      gives = [ "trust" ];
      takes = [
        "cluster"
        "issuance"
        "webhook"
      ];
    };

    coredns-zone = {
      name = "coredns-zone";
      takes = [
        "cluster"
        "zone"
      ];
    };

    gateway = {
      name = "gateway";
      gives = [ "apiGateway" ];
      takes = [
        "cluster"
        "zone"
        "gatewayApi"
        "issuance"
      ];
      inputs.tlsEnable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Fixture input.";
      };
    };

    external-secrets = {
      name = "external-secrets";
      gives = [ "generation" ];
      takes = [ "cluster" ];
    };
  };

  def = import ../clusters/standard-cluster.nix {
    inherit
      lib
      floe
      sigs
      ;
    floes = members;
  };

  outside =
    lib.mapAttrs'
      (
        n: s:
        lib.nameValuePair "outside-${n}" (
          (member {
            name = "outside-${n}";
            gives = [ n ];
          }).instantiate
            { }
        )
      )
      (
        lib.filterAttrs (
          n: _:
          lib.elem n [
            "cluster"
            "zone"
          ]
        ) stubs
      );

  link = floe.link {
    units = outside // {
      platform = def.instantiate { };
    };
  };
in
lib.runTests {

  # The two holes nothing inside answers, and no others. A hole an inclusion
  # declares and nothing inside reads is refused by core, so this is the
  # over-declaration direction; the under-declared one is the unfilled-hole
  # error and cannot reach an assertion.
  testItLeavesTheClaimAndTheZoneOpen = {
    expr = lib.attrNames def.requires;
    expected = [
      "cluster"
      "zone"
    ];
  };

  # Six exports, and the thing that makes an inclusion an interface rather than
  # an arrangement of files: an app beside it resolves against these and
  # nothing else.
  testItExportsWhatAnAppResolvesAgainst = {
    expr = lib.attrNames link.provides.platform;
    expected = [
      "exposure"

      "gateway"
      "gatewayApi"
      "generation"
      "issuance"
      "trust"
      "webhook"
    ];
  };

  # An export arrives sealed to the signature the boundary declared, not to
  # whatever the inner unit happened to provide.
  testAnExportIsSealedToTheDeclaredSignature = {
    expr = lib.attrNames link.provides.platform.gateway;
    expected = lib.attrNames sigs.API_GATEWAY.fields;
  };

  # Nothing inside is addressable from outside. `cert-manager` provides
  # `issuance` and `webhook` in there, and a peer reads them through the
  # boundary's export or not at all.
  testAnInnerUnitIsNotAProviderAtTheParent = {
    expr = lib.attrNames link.provides;
    expected = [
      "outside-cluster"
      "outside-zone"
      "platform"
    ];
  };

  # What lowering reads. A component inside an inclusion needs its resolution
  # visible at the parent, because that is where one bundle's edge to another's
  # is derived — and both halves are qualified, so the provider named here is
  # the unit the elaborator will find under that name.
  testAnInnerUnitsWiringIsVisibleToTheLowerer = {
    expr = link.wiring.one."platform/gateway".gatewayApi;
    expected = {
      instName = "platform/gateway-api";
      provideName = "gatewayApi";
    };
  };
}
