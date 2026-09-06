# Providers a lab may pin, and the tool built with exactly the ones it uses.
#
# RFC 0003 §10: "Provider versions come from whatever pins the provider, read
# rather than reassembled, so the pinned artifact and the declared version
# cannot diverge."
#
# That is load-bearing and it is why nothing here writes a version number.
# nixpkgs' plugin derivations carry `version` and
# `passthru.provider-source-address`, which is the same pair
# `required_providers` wants — so the rendered stack states what the binary in
# the package *is*, and an input bump moves both together or neither.
#
# The alternative was a table of `{ source = "hashicorp/local"; version =
# "2.5.2"; }` beside a separately-pinned binary. Those drift silently: `init`
# is offline against the vendored plugin, so a mismatched constraint fails
# with "no available releases match" on a machine that has the provider
# sitting right there.
{ lib, pkgs }:

let
  # The set a floe may name, keyed by the short name it writes in
  # `resources.<n>.provider`. Deliberately a small allowlist rather than all
  # 174 of nixpkgs': a lab pins what it uses, and a name that is not here is
  # a typo rather than a provider that happens not to be built yet.
  available = {
    # The three that make the resources category testable with no account.
    # A stack of these runs a real plan, a real apply, real state and a real
    # destroy in seconds — which is the whole fast path.
    local = pkgs.opentofu.plugins.hashicorp_local;
    random = pkgs.opentofu.plugins.hashicorp_random;
    null = pkgs.opentofu.plugins.hashicorp_null;
  };

  # `{ source, version }` as `required_providers` wants it, read off the
  # derivation rather than written down.
  #
  # The source address is fully qualified in nixpkgs
  # (`registry.terraform.io/hashicorp/local`) and `required_providers` takes
  # the registry-relative form, so the host is dropped here — the one place
  # the two spellings meet.
  constraintOf = drv: {
    source = lib.concatStringsSep "/" (
      lib.tail (lib.splitString "/" drv.passthru.provider-source-address)
    );
    inherit (drv) version;
  };
in
{
  inherit available;

  constraints = lib.mapAttrs (_: constraintOf) available;

  # The tool, carrying exactly the providers the lab's stacks use.
  #
  # Not every provider in `available`: `init` verifies each one it is handed,
  # and a lab would pay for providers it never names. The CLI looks for this
  # at `<package>/infra/bin/tofu` and says so when a package predates a stack
  # (`cli/src/plan/steps/infra.rs`).
  toolFor =
    used:
    let
      unknown = lib.subtractLists (lib.attrNames available) used;
    in
    if unknown != [ ] then
      throw (
        "infra: no provider is built for ${lib.concatMapStringsSep ", " (n: "'${n}'") unknown}. "
        + "Add it to `lib/tofu-providers.nix`; the lab pins what it uses, so a name that is not "
        + "there is a typo rather than a provider that happens not to be built yet."
      )
    else
      pkgs.opentofu.withPlugins (_: map (n: available.${n}) used);
}
