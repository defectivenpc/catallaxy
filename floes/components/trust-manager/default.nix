# trust-manager: puts the lab's CA in a ConfigMap in every namespace.
#
# It requires X509_ISSUANCE and reads the Secret the CA lives in. In the old
# tree the arrow pointed the other way — cert-manager emitted the `Bundle`
# CRs and read trust-manager's export to know whether it could — which is
# what made the two mutually dependent. Distribution is this floe's job, so
# the Bundle CRs are here and the cycle is gone.
{
  lib,
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "trust-manager";
  summary = "trust-manager, distributing the lab's CA into every namespace that needs it.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.trust-manager.chart}";
      defaultText = lib.literalExpression "cataCharts.trust-manager.chart";
      description = "Store path of the trust-manager Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "cert-manager";
      description = ''
        Namespace the controller runs in, and the one it reads Bundle sources
        from. Defaults to cert-manager's, because the CA Secret it reads is
        there and the controller only looks in one.
      '';
    };

    bundleName = lib.mkOption {
      type = lib.types.str;
      default = "lab-ca-bundle";
      description = "Name of the ConfigMap the CA lands in, in every namespace.";
    };
  };

  # The webhook, because a `Bundle` is a CR the API server has to admit. And
  # issuance, because the CA it distributes is the one that issuer signs
  # from — this floe reads the Secret cert-manager's root Certificate wrote.
  requires.cluster = sigs.KUBERNETES_CLUSTER;
  requires.webhook = sigs.X509_WEBHOOK;
  requires.issuance = sigs.X509_ISSUANCE;

  provides.trust = sigs.TRUST_BUNDLE;

  out.component = kinds.component;
  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        issuance = config.floe.requires.issuance;

        source = issuance.caSecret;

        secretBundleName = "${inputs.bundleName}-secret";
      in
      {
        config.floe.provides.trust = {
          inherit (inputs) namespace;
          secretTargets = true;
          caBundle = {
            name = inputs.bundleName;
            key = "ca.crt";
          };

          caBundleSecret =
            if source == null then
              null
            else
              {
                name = secretBundleName;
                key = "ca.crt";
              };
        };

        config.floe.out.component = kinds.mkComponent {
          backs.trust = [ "bundles" ];
          imagesComplete = true;

          assertions = [
            {
              assertion = source != null;
              message = ''
                the issuer it was given has no CA secret, so there is nothing
                to distribute. That is what a public issuer looks like: its
                chain is already trusted and no bundle is needed.
              '';
            }
          ];

          bundles.trust-manager = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            crds = [ "trust.cert-manager.io/Bundle" ];

            helmCharts.trust-manager = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "trust-manager";
              values = {
                app.trust.namespace = inputs.namespace;
                secretTargets = {
                  enabled = true;
                  authorizedSecretsAll = true;
                };
              };
            };

            images.controller = kinds.mkImage "quay.io/jetstack/trust-manager:v0.22.1";
            images.defaultCAs = kinds.mkImage "quay.io/jetstack/trust-pkg-debian-bookworm:20230311-deb12u1.6";

            ready = kinds.readyDeployment {
              name = "trust-manager";
              namespace = inputs.namespace;
              timeout = "3m";
            };
          };

          bundles.bundles = kinds.mkBundle {
            needs = [ "trust-manager" ];

            secrets = lib.optionals (source != null) [ "*/${secretBundleName}" ];

            externalSecrets = lib.optionals (source != null) [ inputs.bundleName ];

            resources = lib.optionalAttrs (source != null) {
              ca-bundle = {
                apiVersion = "trust.cert-manager.io/v1alpha1";
                kind = "Bundle";
                metadata.name = inputs.bundleName;
                spec = {
                  sources = [
                    {
                      secret = {
                        inherit (source) name key;
                      };
                    }
                  ];
                  target = {
                    configMap.key = "ca.crt";
                    namespaceSelector = { };
                  };
                };
              };

              ca-bundle-secret = {
                apiVersion = "trust.cert-manager.io/v1alpha1";
                kind = "Bundle";
                metadata.name = secretBundleName;
                spec = {
                  sources = [
                    {
                      secret = {
                        inherit (source) name key;
                      };
                    }
                  ];
                  target = {
                    secret.key = "ca.crt";
                    namespaceSelector = { };
                  };
                };
              };
            };

            ready = kinds.readyCondition {
              resource = "bundle/${inputs.bundleName}";
              condition = "Synced";
              timeout = "3m";
            };
          };
        };
      }
    )
  ];
}
