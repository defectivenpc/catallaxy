# External Secrets: pulls values out of a store and materialises them as
# Kubernetes Secrets.
#
# Two bundles, because the CRDs are established long before the webhook is
# admitting `ExternalSecret`s, and a consumer applying one needs the second.
#
# The old floe declared `reaches = [ "openbao/api" ]`. That names a floe not
# in this round, and a netpol rule pointing at a floe nobody enabled renders
# nothing; it comes back with openbao.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "external-secrets";
  summary = "External Secrets, which mints secret values in the cluster.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the external-secrets Helm chart. Required.";
    };

    crds = lib.mkOption {
      type = lib.types.str;
      description = ''
        Store path of the chart's CRD manifests. Separate from the chart
        because they install as their own bundle: the kinds have to be
        established before anything applies one.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "external-secrets";
      description = "Namespace the controller runs in.";
    };
  };

  # The controller and its generator kinds, which is what this floe actually
  # installs. It creates no store, so it cannot answer SECRET_STORE.
  provides.generation = sigs.SECRET_GENERATION;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        crdKinds = [
          "external-secrets.io/ExternalSecret"
          "external-secrets.io/ClusterExternalSecret"
          "external-secrets.io/SecretStore"
          "external-secrets.io/ClusterSecretStore"
          "external-secrets.io/PushSecret"
          "external-secrets.io/ClusterPushSecret"
          "generators.external-secrets.io/Password"
          "generators.external-secrets.io/UUID"
          "generators.external-secrets.io/Fake"
        ];
      in
      {
        config.floe.provides.generation = {
          inherit (inputs) namespace;
          inherit crdKinds;
          generatorApiVersion = "generators.external-secrets.io/v1alpha1";
        };

        config.floe.out.component = kinds.mkComponent {
          backs.generation = [
            "crds"
            "external-secrets"
          ];
          imagesComplete = true;

          bundles.crds = kinds.mkBundle {
            yamls = [ inputs.crds ];
            crds = crdKinds;
          };

          bundles.external-secrets = kinds.mkBundle {
            needs = [ "crds" ];
            createNamespaces = [ inputs.namespace ];

            helmCharts.external-secrets = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "external-secrets";
              values = {
                # The chart installs them too, and two owners of one CRD is a
                # fight the applier loses. The bundle above is the owner.
                installCRDs = false;
              };
            };

            images.controller = kinds.mkImage "oci.external-secrets.io/external-secrets/external-secrets:v0.15.0";

            ready = kinds.readyDeployment {
              name = "external-secrets-webhook";
              namespace = inputs.namespace;
            };
          };
        };
      }
    )
  ];
}
