# cert-manager: the admission webhook, and a self-signed CA to issue from.
#
# Two provides, because there are two facts and consumers want different
# ones. The webhook is admitting `Certificate` CRs long before any issuer can
# sign one; a floe that only needs the kind installed should not wait for a
# CA that may not exist. Splitting them is also half of what removes the
# cycle this floe used to be in — see `lib/floe-catallaxy/sigs.nix`.
#
# It distributes nothing. The old floe emitted trust-manager `Bundle` CRs
# itself, which is what made cert-manager depend on trust-manager while
# trust-manager depended on cert-manager. Distribution moved to the floe
# whose job it is.
#
# ACME and external issuers are not here: no example lab uses one, and every
# lab that wants TLS wants the self-signed CA.
{
  lib,
  catallaxy,
  sigs,
  kinds,
  ...
}:

catallaxy.mkComponentFloe {
  name = "cert-manager";
  summary = "cert-manager, and an issuer for the lab's own certificates.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      description = "Store path of the cert-manager Helm chart. Required.";
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "cert-manager";
      description = "Namespace the controller and webhook run in.";
    };

    issuerName = lib.mkOption {
      type = lib.types.str;
      default = "lab-ca";
      description = "Name of the ClusterIssuer signing from the lab's own CA.";
    };

    caCommonName = lib.mkOption {
      type = lib.types.str;
      default = "catallaxy lab CA";
      description = "Subject common name on the root certificate.";
    };

    rootFromLab = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Take the root from the lab instead of minting one.

        A lab that runs the host ingress already has a root: `cert-generate`
        mints it, HAProxy serves from it, and `import_lab_ca` seeds it into
        this namespace as the issuer's backing Secret before any manifest is
        applied. Minting a second one would overwrite that Secret, and the
        two halves of the lab would then present certificates from different
        chains — a client trusting one rejecting the other, with nothing
        failing loudly enough to say why.

        With this set the floe drops its `SelfSigned` bootstrap issuer and
        its root `Certificate`, and keeps only the `CA` ClusterIssuer that
        reads the Secret. Set it exactly when `lab.proxy.tls.enable` is on.
      '';
    };
  };

  provides.webhook = sigs.X509_WEBHOOK;
  provides.issuance = sigs.X509_ISSUANCE;

  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        webhookReady = "certificate-issuance/webhook/ready";
        issuerReady = "certificate-issuance/issuer/ready";
        caSecretName = "${inputs.issuerName}-ca-secret";

        crdKinds = [
          "cert-manager.io/Certificate"
          "cert-manager.io/Issuer"
          "cert-manager.io/ClusterIssuer"
          "cert-manager.io/CertificateRequest"
          "acme.cert-manager.io/Challenge"
          "acme.cert-manager.io/Order"
        ];
      in
      {
        config.floe.provides.webhook = {
          inherit (inputs) namespace;
          inherit crdKinds;
        };

        config.floe.provides.issuance = {

          # A lab CA is not in any public trust store, and a consumer that
          # cares — an OIDC client checking an issuer's certificate, say —
          # has to be able to ask rather than assume.
          publicIssuer = false;

          issuerRef = {
            name = inputs.issuerName;
            kind = "ClusterIssuer";
          };

          caSecret = {
            name = caSecretName;
            key = "tls.crt";
            inherit (inputs) namespace;
          };
        };

        config.floe.out.component = kinds.mkComponent {
          # `import_lab_ca` writes the Secret to a name and a namespace that
          # are string literals in Rust (`cli/src/host/pki.rs:346-350`), and
          # this floe computes its own from two inputs. They agree only
          # because the defaults happen to match: set `issuerName` and the
          # ClusterIssuer names a Secret nothing creates, the issuer never
          # becomes Ready, and the failure surfaces as a cluster that hangs.
          #
          # Nothing in the floe system can relate a Nix interpolation to a
          # Rust literal, so the check is a plain assertion on the values the
          # CLI is known to use.
          assertions = lib.optionals inputs.rootFromLab [
            {
              assertion = caSecretName == "lab-ca-ca-secret" && inputs.namespace == "cert-manager";
              message =
                "rootFromLab expects the CA at 'cert-manager/lab-ca-ca-secret', which is what "
                + "`cata lab up` writes, but this floe would read "
                + "'${inputs.namespace}/${caSecretName}'. Leave `issuerName` and `namespace` at "
                + "their defaults, or mint the root here by leaving `rootFromLab` false.";
            }
          ];

          backs = {
            webhook = [ "cert-manager" ];
            issuance = [ "issuers" ];
          };

          imagesComplete = true;

          bundles.cert-manager = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            # The chart installs these, so eval cannot see them in
            # `resources` and the derived `kind:` edge has nothing to
            # resolve against. Saying so is what lets a consumer's
            # Certificate wait for the type to exist.
            crds = crdKinds;

            helmCharts.cert-manager = kinds.mkHelmChart {
              inherit (inputs) chart namespace;
              releaseName = "cert-manager";
              values.crds = {
                enabled = true;
                keep = false;
              };
            };

            images.controller = {
              registry = "quay.io";
              repository = "jetstack/cert-manager-controller";
              tag = "v1.17.2";
              digest = null;
            };
            images.webhook = {
              registry = "quay.io";
              repository = "jetstack/cert-manager-webhook";
              tag = "v1.17.2";
              digest = null;
            };
            images.cainjector = {
              registry = "quay.io";
              repository = "jetstack/cert-manager-cainjector";
              tag = "v1.17.2";
              digest = null;
            };
            images.startupapicheck = {
              registry = "quay.io";
              repository = "jetstack/cert-manager-startupapicheck";
              tag = "v1.17.2";
              digest = null;
            };

            # Available says the pods are up; it does not say the webhook is
            # answering. Applying a Certificate before it is gets refused by
            # the API server, which is why the issuers below are a separate
            # bundle gated on this.
            ready = {
              kind = "condition";
              resource = "deployment/cert-manager-webhook";
              namespace = inputs.namespace;
              condition = "Available";
              timeout = "5m";
            };
          };

          # The CA and the issuer that signs from it. A bootstrap
          # `SelfSigned` issuer mints the root; the root's Secret backs the
          # `CA` issuer everything else uses.
          #
          # Unless the lab already holds a root, in which case only the issuer
          # is ours and the Secret arrives before we do.
          bundles.issuers = kinds.mkBundle {
            needs = [ "cert-manager" ];

            # With `rootFromLab` the producer of this Secret leaves the graph:
            # `cata lab up`'s `cert-generate` mints it and the CLI seeds it
            # into the cluster before any manifest is applied. Saying so is
            # what lets the cluster's coherence check and `cata lab lint`
            # distinguish that from a Secret nobody makes.
            externalSecrets = lib.optionals inputs.rootFromLab [
              "${inputs.namespace}/${caSecretName}"
            ];

            resources =
              lib.optionalAttrs (!inputs.rootFromLab) {
                bootstrap-issuer = {
                  apiVersion = "cert-manager.io/v1";
                  kind = "ClusterIssuer";
                  metadata.name = "${inputs.issuerName}-bootstrap";
                  spec.selfSigned = { };
                };

                root-ca = {
                  apiVersion = "cert-manager.io/v1";
                  kind = "Certificate";
                  metadata = {
                    name = inputs.issuerName;
                    inherit (inputs) namespace;
                  };
                  spec = {
                    isCA = true;
                    commonName = inputs.caCommonName;
                    secretName = caSecretName;
                    duration = "87600h";
                    privateKey = {
                      algorithm = "ECDSA";
                      size = 256;
                    };
                    issuerRef = {
                      name = "${inputs.issuerName}-bootstrap";
                      kind = "ClusterIssuer";
                      group = "cert-manager.io";
                    };
                  };
                };
              }
              // {
                lab-ca = {
                  apiVersion = "cert-manager.io/v1";
                  kind = "ClusterIssuer";
                  metadata.name = inputs.issuerName;
                  spec.ca.secretName = caSecretName;
                };
              };

            ready = {
              kind = "condition";
              resource = "clusterissuer/${inputs.issuerName}";
              namespace = inputs.namespace;
              condition = "Ready";
              timeout = "3m";
            };

            verify.issuers-ready = {
              description = "Every ClusterIssuer is Ready, so certificates can actually be signed";
              timeout = "2m";
              expect = null;
              reject = [
                {
                  apiVersion = "cert-manager.io/v1";
                  kind = "ClusterIssuer";
                  ${kinds.conditionIsNot { type = "Ready"; }} = true;
                }
              ];
            };
          };
        };
      }
    )
  ];
}
