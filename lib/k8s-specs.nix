{
  lib,
  pkgs,
  cataCharts,
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

  # The version is a field and the URL is built from it, so the tag a floe
  # reports and the file it installs cannot disagree. It used to appear twice:
  # here, inside the URL, and again as a literal in every lab.
  standaloneCrdDefs = {
    gateway-api = {
      version = "v1.2.1";
      url =
        version:
        "https://github.com/kubernetes-sigs/gateway-api/releases/download/${version}/experimental-install.yaml";
      hash = "sha256-06pnI6MwZ3DP+2Ae4irz012kOs+hylR/wNO84I2tZuc=";
    };
  };

  standaloneCrds = lib.mapAttrs (
    name: def:
    pkgs.fetchurl {
      url = def.url def.version;
      inherit (def) hash;
      name = "${name}-crds.yaml";
    }
  ) standaloneCrdDefs;

  standaloneCrdVersions = lib.mapAttrs (_: def: def.version) standaloneCrdDefs;

in
{
  # `specs` is the input to `lib/kubernetes/generated/`, wired to it by
  # nothing; it records which API versions those were generated from.
  inherit specs standaloneCrds standaloneCrdVersions;
}
