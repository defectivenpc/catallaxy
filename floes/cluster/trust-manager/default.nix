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
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "trust-manager";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
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

  requires.cluster = sigs.KUBERNETES_CLUSTER;

  # The webhook, because a `Bundle` is a CR the API server has to admit. And
  # issuance, because the CA it distributes is the one that issuer signs
  # from — this floe reads the Secret cert-manager's root Certificate wrote.
  requires.webhook = sigs.X509_WEBHOOK;
  requires.issuance = sigs.X509_ISSUANCE;

  provides.distribution = sigs.TRUST_BUNDLE;
  out.component = kinds.component;

  modules = [
    (
      { config, lib, ... }:
      let
        inputs = config.floe.inputs;
        issuance = config.floe.requires.issuance;
        readyToken = "trust-manager/bundles/ready";

        source = issuance.caSecret;

        # One binding, three projections: the Bundle that writes it, the
        # `secrets` declaration that tells the cluster it exists, and the
        # provide a consumer reads. Computing it twice is what the projection
        # rule forbids, and this name is exactly the kind that would drift.
        secretBundleName = "${inputs.bundleName}-secret";
      in
      {
        config.floe.provides.distribution = {
          inherit readyToken;
          inherit (inputs) namespace;
          secretTargets = true;
          caBundle = {
            name = inputs.bundleName;
            key = "ca.crt";
          };

          # The Secret-shaped copy was already being written into every
          # namespace and its name appeared nowhere, so a consumer had to
          # know it. Projected from the same binding as the Bundle that
          # writes it, per the projection rule.
          #
          # Null when there is no CA to distribute, because that is when the
          # Bundles are not rendered either — a name for a Secret nothing
          # writes is worse than saying there is none.
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
          backs.distribution = [ "bundles" ];
          imagesComplete = true;

          network = {
            declared = true;
            serves.webhook = {
              port = 6443;
              fromApiServer = true;
            };
          };

          # A public issuer has no CA to hand out, so there is nothing to
          # distribute and the floe should not have been enabled. Said rather
          # than silently rendering a Bundle with no source.
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

            # Installed by the chart, so declared here: the Bundle CRs in the
            # next bundle are what wait on it.
            crds = [ "trust.cert-manager.io/Bundle" ];

            helmCharts.trust-manager = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "trust-manager";
              values = {
                app.trust.namespace = inputs.namespace;
                # Without this a `target.secret` Bundle stays silently
                # pending: the controller starts with no Secret-write RBAC.
                secretTargets = {
                  enabled = true;
                  authorizedSecretsAll = true;
                };
              };
            };

            images.controller = {
              registry = "quay.io";
              repository = "jetstack/trust-manager";
              tag = "v0.22.1";
              digest = null;
            };
            images.defaultCAs = {
              registry = "quay.io";
              repository = "jetstack/trust-pkg-debian-bookworm";
              tag = "20230311-deb12u1.6";
              digest = null;
            };

            ready = {
              kind = "condition";
              resource = "deployment/trust-manager";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "3m";
            };
          };

          bundles.bundles = kinds.mkBundle {
            needs = [ "trust-manager" ];

            # The controller writes this into every namespace, so neither the
            # walk over `resources` — which sees a Bundle, not a Secret — nor
            # a namespace-qualified name can express it.
            secrets = lib.optionals (source != null) [ "*/${secretBundleName}" ];

            # The ConfigMap half, declared for the same reason and until now
            # not declared at all: this is the target a consumer actually
            # mounts, and nothing said it would exist. The first floe to mount
            # it — netbird, verifying the issuer it was handed — was reported
            # as referencing a ConfigMap that does not exist, which was true
            # of the manifest stream and false of the cluster.
            #
            # Bare, with no namespace: it lands in all of them, and a
            # declaration that cannot know its consumer's namespace has
            # nothing else to say.
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
                    # Every namespace. A workload that has to trust the lab
                    # CA is not knowable from here, and an empty selector is
                    # cheaper than being told.
                    namespaceSelector = { };
                  };
                };
              };

              # The same bundle as a Secret, for the consumers that can only
              # mount a CA from one — harbor's `caBundleSecret`, and most
              # things that take a client certificate beside it.
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

            # The Bundle's own status, not the ConfigMap it produces.
            #
            # Waiting on the ConfigMap waits on a resource this bundle does not
            # render — the controller writes it, into every namespace — so
            # nothing could relate the probe to what was applied, and
            # `cata lab lint`'s ready-probe rule said so. `Synced` is the
            # signal trust-manager publishes when the distribution is done,
            # which is the thing actually being waited for.
            ready = {
              kind = "condition";
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
