# Every chart value a floe writes does something. See `chart-values.py`.
{
  lib,
  pkgs,
  labDefs,
}:

let
  instantiations = lib.concatLists (
    lib.mapAttrsToList (
      labName: lab:
      lib.concatLists (
        lib.mapAttrsToList (
          clusterName: cluster:
          lib.concatLists (
            lib.mapAttrsToList (
              bundleName: bundle:
              lib.mapAttrsToList (chartName: chart: {
                where = "${labName}/${clusterName} ${bundleName}/${chartName}";
                chart = "${chart.chart}";
                inherit (chart) values;
              }) (bundle.helmCharts or { })
            ) (cluster.out.bundles or { })
          )
        ) lab.clusters
      )
    ) labDefs
  );
in
{
  chart-values =
    pkgs.runCommand "chart-values-tests"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.kubernetes-helm
          pkgs.yq-go
        ];
        passAsFile = [ "instantiations" ];
        instantiations = builtins.toJSON instantiations;
      }
      ''
        export HELM_CACHE_HOME=$PWD/.helm \
               HELM_CONFIG_HOME=$PWD/.helm \
               HELM_DATA_HOME=$PWD/.helm

        python3 ${./chart-values.py} "$instantiationsPath" | tee $out
      '';
}
