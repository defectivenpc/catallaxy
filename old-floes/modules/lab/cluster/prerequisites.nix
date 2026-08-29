{ config, lib, ... }:

let
  inherit (lib) mkOption types;
  inherit (import ./prerequisite-types.nix { inherit lib; }) prerequisiteType;
in
{
  options.cluster.prerequisites = mkOption {
    type = types.attrsOf prerequisiteType;
    default = { };
    example = lib.literalExpression ''
      {
        gateway-api-crds = {
          yamls = [ k8sSpecs.standaloneCrds.gateway-api ];
          provides = [ "gateway-api/crds/established" ];
        };
      }
    '';
    description = ''
      Things several floes need installed and exactly one installation of
      which is correct. Each key becomes one bundle the cluster owns, holding
      the union of what every contributor asked for.

      A floe declaring a bundle directly is stamped with its name for
      `floe:<name>` anchors, so two floes declaring the same bundle is a
      conflicting definition rather than a merge: enabling cilium and gateway
      together failed outright, because both install the Gateway API CRDs.
      That is not two floes fighting, it is one thing both of them need, and
      the stamp is right to refuse an owner that is genuinely ambiguous.
      Declaring it here says the cluster owns it, which is true, so there is
      no owner to disagree about.

      Distinct from `cluster.bootstrapManifests`, which is what the cluster
      needs before its nodes are Ready and so has to arrive through the
      provisioner. A prerequisite is installed by the deploy like anything
      else; it just has more than one floe asking for it.
    '';
  };

  config.bundles = lib.mapAttrs (_: prereq: {
    declaredBy = "cluster";
    owner = {
      bootstrap = "install-target";
      steady = "argocd";
    };
    yamls = lib.unique prereq.yamls;
    provides = lib.unique prereq.provides;
    requires = lib.unique prereq.requires;
    after = lib.unique prereq.after;
    conflicts = lib.unique prereq.conflicts;
  }) config.cluster.prerequisites;
}
