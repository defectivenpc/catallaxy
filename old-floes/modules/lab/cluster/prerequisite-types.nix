# The type of one cluster prerequisite.
#
# Split out of `prerequisites.nix` so the floe interface can declare a
# `prerequisites` contribution channel of the same type without importing a
# module to reach inside it. Same reason `lint-types.nix`,
# `verify-types.nix` and `network-policy-types.nix` exist.
{ lib }:

let
  inherit (lib) mkOption types;
in
{
  prerequisiteType = types.submodule {
    options = {
      yamls = mkOption {
        type = types.listOf (types.either types.str types.path);
        default = [ ];
        description = "Rendered manifests the prerequisite installs, deduplicated across contributors.";
      };

      provides = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names this supplies, in the one dependency namespace.";
      };

      requires = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names that must be supplied and READY before this applies.";
      };

      after = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names that must be supplied and APPLIED before this. Ordering only.";
      };

      conflicts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names a second provider of would be a race rather than a merge.";
      };
    };
  };
}
