# Every custom resource a floe renders has a schema to be checked against.
#
# `conform.nix` checks a resource against the generated type its `apiVersion`
# and `kind` name. When nothing describes that kind it checks against nothing,
# and says nothing — so an `apiVersion` typo and a legitimately uncovered kind
# look identical, and both pass. This is what tells them apart.
#
# The exemption is derived rather than listed. A bundle that declares `crds`
# but carries neither `yamls` nor `helmCharts` installs no CRD content: its
# kinds arrive when some controller does, long after the manifest that asked
# for them was applied, so no extractor in `nix/crd-types.nix` could have read
# them. `crossplane-provider-nop` is the case — crossplane installs the nop
# provider's CRDs when the provider goes healthy.
#
# Derived, so it cannot go stale. The day those CRDs become extractable and
# land in `nix/crd-types.nix`, the kind gets a schema and stops being reported
# whatever this check believes. A name in a list would have had to be noticed
# and removed.
{
  lib,
  pkgs,
  labDefs,
}:

let
  k8sTypes = import ../../lib/kubernetes/types.nix { inherit lib; };
  inherit (k8sTypes) coreKinds typesByKind;
  inherit (k8sTypes.generatedTypes) resolveResourceType;

  groupOf = apiVersion: lib.head (lib.splitString "/" apiVersion);

  # A bundle whose CRDs some controller installs, not this manifest set.
  installsNoCrdContent =
    b: (b.crds or [ ]) != [ ] && (b.yamls or [ ]) == [ ] && (b.helmCharts or { }) == { };

  findingsFor =
    labName: lab:
    lib.concatLists (
      lib.mapAttrsToList (
        clusterName: cluster:
        let
          bundles = cluster.out.bundles or { };

          runtimeKinds = lib.unique (
            lib.concatLists (
              lib.mapAttrsToList (_: b: lib.optionals (installsNoCrdContent b) (b.crds or [ ])) bundles
            )
          );

          uncovered = lib.concatLists (
            lib.mapAttrsToList (
              bundleName: b:
              lib.concatLists (
                lib.mapAttrsToList (
                  resName: r:
                  let
                    av = r.apiVersion or "";
                    kind = r.kind or "";
                  in
                  if coreKinds ? ${kind} || resolveResourceType typesByKind av kind != null then
                    [ ]
                  else if lib.elem "${groupOf av}/${kind}" runtimeKinds then
                    [ ]
                  else
                    [
                      "${labName}/${clusterName} ${bundleName}/${resName}: ${av}/${kind} has no generated schema"
                    ]
                ) (b.resources or { })
              )
            ) bundles
          );
        in
        uncovered
      ) lab.clusters
    );

  findings = lib.concatLists (lib.mapAttrsToList findingsFor labDefs);
in
{
  crd-coverage = pkgs.runCommand "crd-coverage-tests" { } ''
    ${lib.concatMapStringsSep "\n" (f: "echo ${lib.escapeShellArg f} >&2") findings}
    ${lib.optionalString (findings != [ ]) ''
      echo "" >&2
      echo "A resource of this kind is checked against nothing, and nothing" >&2
      echo "said so. An \`apiVersion\` typo looks exactly like this." >&2
      echo "" >&2
      echo "Generate its types: add the chart or release YAML that defines" >&2
      echo "the CRD to \`nix/crd-types.nix\`, then \`nix run" >&2
      echo ".#refresh-generated-types\`." >&2
      echo "" >&2
      echo "If the CRDs genuinely arrive at runtime — a controller installs" >&2
      echo "them after this manifest applies — then the bundle establishing" >&2
      echo "them should declare \`crds\` and carry no \`yamls\` or" >&2
      echo "\`helmCharts\`, which is how that case is recognised." >&2
      exit 1
    ''}
    echo "every rendered custom resource resolves to a schema" > $out
  '';
}
