# The containers a lab runs on the host, and nothing else.
#
# `lab.out.services` lives here rather than in `out.nix` because two things
# read it: the plan, which emits `setup-services` only when there is something
# to start, and `cliConfig`, which carries the records themselves. `cliConfig`
# already reads the plan, so computing the set there would close a loop.
#
# The attribute keys are part of the CLI contract, not labels. Each one is the
# name of the service's state directory (`cli/src/host/state.rs:32`), and
# `"registry"`, `"dns"` and `"proxy"` are additionally looked up by literal
# string — `create_cluster.rs:15` finds `registries.yaml` under the first, and
# `import_lab_ca` is gated on the third existing.
{ config, lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  imports = [
    ../network/dns.nix
    ./registry.nix
    ./proxy.nix
    ./egress.nix
  ];

  options.lab.out.services = mkOption {
    type = types.attrsOf types.attrs;
    internal = true;
    readOnly = true;
    description = "Every enabled host service, keyed by the name the CLI knows it as.";
  };

  config.lab.out.services =
    lib.optionalAttrs config.lab.dns.enable { dns = config.lab.dns.out.service; }
    // lib.optionalAttrs config.lab.registry.enable { registry = config.lab.registry.service; }
    // lib.optionalAttrs config.lab.proxy.enable { proxy = config.lab.proxy.out.service; }
    // lib.optionalAttrs config.lab.egress.enable { egress = config.lab.egress.out.service; };
}
