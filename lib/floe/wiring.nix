# Typed cross-floe wiring: a floe names a job, not a floe.
#
# `peers` fixed the *boundary* — a floe sees siblings' `exports` and nothing
# else. It did not fix the *dependency*, and the spike's own notes were honest
# about that: "an absent peer read at option-default time still fails, exactly
# as today. A floe set containing harbor still needs gateway, cert-manager,
# kanidm, kaniop and trust-manager."
#
# The failure is what makes it worth fixing. Reading `peers.gateway.gatewayName`
# when gateway is not in the set is a missing-attribute error, which
# `builtins.tryEval` cannot even catch, and which names neither the floe that
# needed it nor the thing it needed. This turns that into a sentence.
#
# ## What the author writes
#
#     dependencies.gateway.capability = "api-gateway";
#     …
#     parentRefs = [ { name = deps.gateway.routing.publicReady; } ];
#
# and never writes `peers.gateway`. The slot name is local — it is what *this*
# floe calls the thing — and the capability is the contract.
#
# ## Where the type safety comes from
#
# Not from the provider. `lib/contracts/api-gateway.nix` declares the shape of
# the job and its `claim` already validates a provider's payload against it,
# rejecting unknown fields and requiring the ones with no default. So what a
# consumer reads through `deps` is the *contract's* surface, which is the same
# whichever floe is providing it. That is the plug-in point: an author adds a
# contract under `lib/contracts/`, and both halves — the provider's `claim` and
# the consumer's `deps` — are typed by it.
{ lib }:

let
  inherit (lib)
    mkOption
    types
    attrNames
    filterAttrs
    concatStringsSep
    ;
in
rec {
  requirementType = types.submodule {
    options = {
      capability = mkOption {
        type = types.str;
        example = "api-gateway";
        description = ''
          The job this floe needs done, as a name in the capability namespace
          — never the name of a floe.

          Naming the job is what lets a lab swap zot for harbor, or traefik
          for cilium's gateway, without the consumer changing.
        '';
      };

      optional = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether the floe still works with nothing providing this.

          When true and nothing provides it, the slot resolves to `null`
          instead of failing, and the floe is responsible for handling that.
          When false — the default — an unprovided slot is an error naming
          this floe and this capability.
        '';
      };
    };
  };

  /**
    Resolve one floe's declared dependencies against what its peers provide.

    `peerCapabilities` is `<floe> = <capabilities.provides>` for the siblings,
    lazily; `dependencies` is what this floe declared. The result is
    `<slot> = <the contract payload the provider claimed>`.

    Errors are `throw`s rather than assertions on purpose. An assertion is
    collected and reported at the end, which is right for "this configuration
    is invalid" — but an unresolved slot is read *while evaluating the floe*,
    so by the time assertions are gathered the read has already failed with
    something worse. A throw here is catchable (`builtins.tryEval` catches
    `throw`; it cannot catch the missing-attribute error this replaces) and it
    arrives at the moment of the read.
  */
  resolve =
    {
      floeName,
      dependencies,
      peerCapabilities,
    }:
    lib.mapAttrs (
      slot: requirement:
      let
        providers = filterAttrs (_: caps: caps ? ${requirement.capability}) peerCapabilities;

        providerNames = attrNames providers;

        available = lib.unique (
          lib.concatLists (lib.mapAttrsToList (_: caps: attrNames caps) peerCapabilities)
        );
      in
      if providerNames == [ ] then
        if requirement.optional then
          null
        else
          throw ''
            floe `${floeName}` needs a floe providing `${requirement.capability}` for its `${slot}` dependency, and this floe set has none.

            ${
              if available == [ ] then
                "No floe in the set provides any capability."
              else
                "The set provides: ${concatStringsSep ", " (map (c: "`${c}`") available)}."
            }

            Either add a floe that claims `${requirement.capability}` in its
            `capabilities.provides`, or mark the slot
            `dependencies.${slot}.optional = true` and handle the null.
          ''
      else if lib.length providerNames > 1 then
        throw ''
          floe `${floeName}`'s `${slot}` dependency on `${requirement.capability}` is ambiguous: ${
            concatStringsSep " and " (map (n: "`${n}`") providerNames)
          } both provide it.

          Two providers of one job is a race rather than a merge. Disable one,
          or say which is meant on the bundle with `conflicts`.
        ''
      else
        providers.${lib.head providerNames}.${requirement.capability}
    ) dependencies;
}
