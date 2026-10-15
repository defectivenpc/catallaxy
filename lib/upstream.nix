/*
  How a floe pins the upstream thing it vendors, and how CRDs are taken out of
  it.

      upstream.helm {
        repo = "https://charts.jetstack.io";
        chart = "cert-manager";
        version = "1.17.2";
        hash = "sha256-8d/BPet3MNGd8n0r5F1HEW4Rgb/UfdtwqSFuUZTyKl4=";
      }

      upstream.release {
        name = "cert-manager";
        url = "https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.crds.yaml";
        hash = "sha256-uV5UEebfhwdm3May91pRmPwFS+YUM5L6KDzfi0BMfzU=";
      }

  Three fetchers and three ways to reach the CRDs in what they fetched:

  | the CRDs are...                  | use              |
  | -------------------------------- | ---------------- |
  | a `crds/` directory in the chart | `crdsInChart`    |
  | templates the chart renders      | `crdsInTemplate` |
  | the whole of a release file      | `release`        |
  | files under a path in a git tree | `crdsInTree`     |

  This is a library of combinators, not a registry. Nothing here knows which
  charts exist — a floe states its own pin, in its own `upstream.nix`, and
  what you get back is a derivation. A central table of pins is what let a
  duplicate of `local-path-provisioner` and a pin for a floe that installs no
  chart both sit unnoticed.

  Every CRD artifact is named `<name>-crds.yaml`. That is load-bearing: the
  manifest digests normalise store hashes but not store names, so renaming one
  moves a committed oracle without changing a byte of content.
*/
{
  lib,
  pkgs,
  kubelib,
}:

let
  # Concatenated with a leading `---` per file, so the result is one stream
  # whatever it came from, and an empty input is an empty file rather than an
  # error — a chart with no `crds/` is a normal chart.
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
  /*
    A Helm chart, pinned. `hash` is the chart tarball's.

    The returned derivation is the unpacked chart, which is what a floe's
    `chart` option wants and what `crdsInChart` and `crdsInTemplate` read.
  */
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

  /*
    A single file published at a URL — a release's `crds.yaml`, a manifest
    bundle. Whatever is at the URL is the artifact; nothing is filtered out,
    so point this at something that is only CRDs.
  */
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

  /*
    The chart's own `crds/` directory, which is where Helm puts CRDs it
    installs before templating and never upgrades.
  */
  crdsInChart = name: chart: concatYaml name ''ls "${chart}"/crds/*.yaml 2>/dev/null || true'';

  /*
    The CRDs a chart renders as ordinary templates, which Helm will upgrade
    and which therefore cannot live in `crds/`.

    Fails when rendering produces none, because that is not a chart without
    CRDs — it is this pin claiming CRDs it no longer renders.
  */
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

  /*
    Files under a path in a git tree, for a project that publishes its CRDs in
    the repository rather than in the chart. `glob` defaults to `*.yaml`.
  */
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
