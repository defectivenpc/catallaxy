{ lib, pkgs }:

# Lowering an evaluated cluster to the JSON the CLI reads.
#
# There used to be an evaluator here as well — `baseModules`, `evalCluster`,
# `evalClusterConfig`, `evalClusterJSON` — and it could not have worked:
# `baseModules` was `[ ../modules ]`, which resolves to `lib/modules`, a
# directory that does not exist. Nothing called any of it, and Nix's laziness
# meant the broken path was never forced, so it sat here looking like API.
# `lib/tests/cluster-lint.nix` defines its own `evalCluster` against the real
# `modules/lab`, which is presumably how the breakage went unnoticed.

let

  clusterConfigToJSON = config: {
    inherit (config.cluster) name provider provisioner;
    kubeContext = config.cluster.ref.kubeContext;
    kubernetes = config.cluster.kubernetes;
    talos = config.cluster.talos;
    network = config.cluster.network;

    manifestWaves = config.cluster.out.manifestWaves or [ ];

    exposedHosts = config.cluster.out.exposedHosts or [ ];

    trust = config.cluster.trust;

    apiserver = config.cluster.apiserver;

    floes = lib.mapAttrs (name: floe: {
      enable = floe.enable or false;
      version = floe.version or null;
      namespace = floe.namespace or name;
      domain =
        let
          v = builtins.tryEval (floe.domain or "");
        in
        if v.success then v.value else "";
    }) (config.floes or { });
    provisionerConfig = {
      docker = {
        clusterName = config.provisioner.docker.clusterName or "";
        waitTimeout = config.provisioner.docker.waitTimeout or "10m";
        colima = config.provisioner.docker.colima or { };
      };
      talos = {
        clusterName = config.provisioner.talos.clusterName or "";
        image = config.provisioner.talos.image or null;
        kubernetesVersion = config.provisioner.talos.kubernetesVersion or null;
        subnet = config.provisioner.talos.subnet or "10.5.0.0/24";
        exposedPorts = config.provisioner.talos.exposedPorts or [ ];
        mounts = config.provisioner.talos.mounts or [ ];
        memory = config.provisioner.talos.memory or "2.0GiB";
        cpus = config.provisioner.talos.cpus or "2.0";
        configPatches = config.provisioner.talos.configPatches or [ ];
        reachableFrom = config.provisioner.talos.reachableFrom or [ ];
      };
      k3d = {
        clusterName = config.provisioner.k3d.clusterName or "";
        image = config.provisioner.k3d.image or null;
        noTraefik = config.provisioner.k3d.noTraefik or true;
        noServiceLB = config.provisioner.k3d.noServiceLB or false;
        noFlannel = config.provisioner.k3d.noFlannel or true;
        noLocalStorage = config.provisioner.k3d.noLocalStorage or false;
        network = config.provisioner.k3d.network or null;
        ports = config.provisioner.k3d.ports or [ ];
        extraApiServerArgs = config.provisioner.k3d.extraApiServerArgs or [ ];
        extraVolumes = config.provisioner.k3d.extraVolumes or [ ];
        autoDeployManifests = map (m: {
          name = m.name;
          path = toString m.content;
        }) (config.provisioner.k3d.autoDeployManifests or [ ]);
      };
    };
    deploy =
      if config ? deploy then
        {
          inherit (config.deploy) strategy;
          kapp = config.deploy.kapp;
          argocd = config.deploy.argocd;
          fleet = config.deploy.fleet;
        }
      else
        {
          strategy = "kapp";
          kapp = { };
          argocd = { };
          fleet = { };
        };
    resources = lib.mapAttrs (name: rset: {
      inherit (rset) namespace;
      appName = "resources-${name}";
    }) (config.resources or { });
    crds = lib.mapAttrs (name: crd: {
      inherit (crd) waitForEstablished crdNames;
      paths = map toString crd.source.paths;
    }) (lib.filterAttrs (_: crd: crd.enable) (config.crds or { }));
    projections = lib.mapAttrs (name: proj: {
      inherit (proj) source namespace;
      keys = lib.mapAttrs (kname: key: {
        inherit (key) from transform;
        jsonKey = key.jsonKey or null;
      }) proj.keys;
    }) ((config.secrets or { }).projections or { });

    secrets = lib.mapAttrs (name: sec: {
      namespace = sec.namespace or "default";
      backend = sec.backend or "sops";
    }) ((config.secrets or { }).managed or { });
    outputs = config.cluster.out;
    lifecycle =
      let

        hookBin =
          step:
          let
            mainProgram = step.package.meta.mainProgram or null;
          in
          if mainProgram != null then
            "${step.package}/bin/${mainProgram}"
          else
            "${step.package}/bin/${step.name}";
      in
      {
        preProvision = map (step: {
          inherit (step) name description order;
          bin = hookBin step;
        }) (lib.sort (a: b: a.order < b.order) (config.lifecycle.preProvision or [ ]));
      };
  };

in
{
  inherit clusterConfigToJSON;
}
