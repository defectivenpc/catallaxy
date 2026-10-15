{
  lib,
  pkgs,
}:

let
  specDefs = {
    "1.31" = {
      url = "https://raw.githubusercontent.com/kubernetes/kubernetes/v1.31.7/api/openapi-spec/swagger.json";
      hash = "sha256-3cs9XD2FhJ8frbVjh9Onv0RxLaKR5b0Is0306KQkf40=";
    };
  };

  specs = lib.mapAttrs (
    version: def:
    pkgs.fetchurl {
      inherit (def) url hash;
      name = "k8s-swagger-${version}.json";
    }
  ) specDefs;

in
{
  # `specs` is the input to `lib/kubernetes/generated/`, wired to it by
  # nothing; it records which API versions those were generated from.
  inherit specs;
}
