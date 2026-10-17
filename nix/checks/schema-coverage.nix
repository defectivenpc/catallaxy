/*
  How much of the Kubernetes API `T` can express, pinned.

  `lib/kubernetes/schema-to-type.nix` converts the pinned OpenAPI spec at
  evaluation time. Where `T` has no word for a construct it yields `T.any`,
  and the point of recording that is this check: the gap is a number that
  moves when the spec does, rather than a property of the output nobody can
  see.

  Pinned rather than bounded, because either direction is worth reading. More
  fallbacks means a Kubernetes release introduced something `T` cannot say;
  fewer means `T` grew or a definition changed shape.
*/
{
  lib,
  pkgs,
  floeCore,
  k8sSpecs,
}:

let
  fromSpec = import ../../lib/kubernetes/schema-to-type.nix {
    inherit lib;
    T = floeCore.T;
  };

  converted = fromSpec {
    spec = builtins.fromJSON (builtins.readFile k8sSpecs.specs."1.31");
  };

  # Each one is `T.any` and says why. Four, as of Kubernetes 1.31: three
  # numeric bounds inside the CRD meta-schema, which describes arbitrary JSON
  # Schema, and `IntOrString`, which is a union of two primitives.
  expected = [
    "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps.maximum"
    "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps.minimum"
    "io.k8s.apiextensions-apiserver.pkg.apis.apiextensions.v1.JSONSchemaProps.multipleOf"
    "io.k8s.apimachinery.pkg.util.intstr.IntOrString"
  ];

  found = lib.sort lib.lessThan (map (f: f.path) converted.fallbacks);
  wanted = lib.sort lib.lessThan expected;

  reasons = lib.concatMapStringsSep "\n" (f: "  ${f.path}\n    ${f.why}") converted.fallbacks;
in
{
  schema-coverage =
    pkgs.runCommand "schema-coverage"
      {
        inherit reasons;
        surprises = lib.concatStringsSep "\n" (lib.subtractLists wanted found);
        resolved = lib.concatStringsSep "\n" (lib.subtractLists found wanted);

        definitions = toString (lib.length (lib.attrNames converted.types));
        kinds = toString (lib.length (lib.attrNames converted.coreKinds));
      }
      ''
        if [ -n "$surprises" ]; then
          echo "the Kubernetes spec has a construct `T` cannot express and this did not:" >&2
          printf '%s\n' "$surprises" | sed 's/^/  /' >&2
          echo "" >&2
          echo "Either give `T` a word for it, or add it to `expected` in" >&2
          echo "nix/checks/schema-coverage.nix with the reason it prints." >&2
          exit 1
        fi

        if [ -n "$resolved" ]; then
          echo "these are listed as unexpressible and now convert:" >&2
          printf '%s\n' "$resolved" | sed 's/^/  /' >&2
          echo "Drop them from `expected`." >&2
          exit 1
        fi

        {
          echo "$definitions definitions, $kinds kinds, and these fall back to T.any:"
          printf '%s\n' "$reasons"
        } > $out
      '';
}
