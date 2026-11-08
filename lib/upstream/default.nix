{
  lib,
  pkgs,
  kubelib,
}:

let
  concatYaml =
    name: filesCommand:
    pkgs.runCommand "${name}-crds.yaml" { } ''
      { ${filesCommand}; } | while read -r f; do
        printf '\n---\n' >> $out
        cat "$f" >> $out
      done
      if [ ! -s "$out" ]; then touch $out; fi
    '';

  crdFilter = "select(.kind == \"CustomResourceDefinition\")";
in
{

  helm =
    {
      repo,
      chart,
      version,
      hash,
    }:
    kubelib.downloadHelmChart {
      inherit repo chart version;
      chartHash = hash;
    };

  release =
    {
      name,
      url,
      hash,
    }:
    pkgs.fetchurl {
      inherit url hash;
      name = "${name}-crds.yaml";
    };

  crdsInChart = name: chart: concatYaml name ''ls "${chart}"/crds/*.yaml 2>/dev/null || true'';

  crdsInTemplate =
    name: chart:
    pkgs.runCommand "${name}-crds.yaml"
      {
        nativeBuildInputs = [
          pkgs.kubernetes-helm
          pkgs.yq-go
        ];
      }
      ''
        export HELM_CACHE_HOME=$PWD/.helm HELM_CONFIG_HOME=$PWD/.helm HELM_DATA_HOME=$PWD/.helm
        helm template ${name} ${chart} \
          | yq '${crdFilter}' - > $out
        if [ ! -s "$out" ]; then
          echo "${name} declares its CRDs as templates but rendering produced none," >&2
          echo "so either the chart moved them or the values now gate them off." >&2
          exit 1
        fi
      '';

  crdsInTree =
    name:
    {
      owner,
      repo,
      rev,
      hash,
      path,
      glob ? [ "*.yaml" ],
    }:
    let
      src = pkgs.fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
      findArgs = lib.concatStringsSep " -o " (map (g: "-name '${g}'") glob);
    in
    concatYaml name ''find "${src}/${path}" \( ${findArgs} \) -type f | sort'';
}
