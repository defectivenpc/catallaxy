# Providers a lab may pin, and the tool built with exactly the ones it uses.
{ lib, pkgs }:

let
  available = {
    local = pkgs.opentofu.plugins.hashicorp_local;
    random = pkgs.opentofu.plugins.hashicorp_random;
    null = pkgs.opentofu.plugins.hashicorp_null;

    digitalocean = pkgs.opentofu.plugins.digitalocean_digitalocean;
  };

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
