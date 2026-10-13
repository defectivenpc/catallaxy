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
  floe,
  cataCharts ? null,
  sigs,
  kinds,
  ...
}:

floe.mkFloe {
  name = "cert-manager";
  summary = "cert-manager, and an issuer for the lab's own certificates.";

  inputs = {
    chart = lib.mkOption {
      type = lib.types.str;
      default = "${cataCharts.cert-manager.chart}";
      defaultText = lib.literalExpression "cataCharts.cert-manager.chart";
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

  };

  requires.cluster = sigs.KUBERNETES_CLUSTER;
  provides.webhook = sigs.X509_WEBHOOK;
  provides.issuance = sigs.X509_ISSUANCE;

  # The lab's root, when there is one. Resolved means "sign from it": the
  # floe drops its `SelfSigned` bootstrap issuer and its root `Certificate`
  # and keeps only the `CA` ClusterIssuer reading the Secret `cata lab up`
  # seeded. Minting a second root would overwrite that Secret, and the two
  # halves of the lab would present certificates from different chains — a
  # client trusting one rejecting the other, with nothing failing loudly
  # enough to say why.
  #
  # It was a `rootFromLab` boolean whose description said "set it exactly when
  # `lab.proxy.tls.enable` is on", beside an assertion comparing this floe's
  # computed Secret name against a Rust literal — because nothing in the floe
  # system could relate a Nix interpolation to one. Resolving the signature is
  # both statements, and the address comes off it.
  optional.labCa = sigs.LAB_CA;

  out.component = kinds.component;
  modules = [
    (
      { config, ... }:
      let
        inputs = config.floe.inputs;

        webhookReady = "certificate-issuance/webhook/ready";
        issuerReady = "certificate-issuance/issuer/ready";
        labCa = config.floe.requires.labCa;
        fromLab = labCa != null;

        caSecretName = if fromLab then labCa.secret.name else "${inputs.issuerName}-ca-secret";
        caSecretNamespace = if fromLab then labCa.secret.namespace else inputs.namespace;

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

          publicIssuer = false;

          issuerRef = {
            name = inputs.issuerName;
            kind = "ClusterIssuer";
          };

          caSecret = {
            name = caSecretName;
            key = "tls.crt";
            namespace = caSecretNamespace;
          };
        };

        config.floe.out.component = kinds.mkComponent {

          backs = {
            webhook = [ "cert-manager" ];
            issuance = [ "issuers" ];
          };

          imagesComplete = true;

          bundles.cert-manager = kinds.mkBundle {
            createNamespaces = [ inputs.namespace ];

            crds = crdKinds;

            helmCharts.cert-manager = kinds.mkHelmChart {
              replacedHooks = {
                cert-manager-startupapicheck =
                  "the webhook bundle waits on `readyDeployment cert-manager-webhook`, "
                  + "and the issuer bundle on the ClusterIssuer reporting Ready \u2014 which "
                  + "proves a CR was accepted *and* reconciled, not merely admitted";
                "cert-manager-startupapicheck:create-cert" =
                  "same probe; this is the second half of the same check";
              };
              inherit (inputs) chart namespace;
              releaseName = "cert-manager";
              values.crds = {
                enabled = true;
                keep = false;
              };
            };

            images.controller = kinds.mkImage "quay.io/jetstack/cert-manager-controller:v1.17.2";
            images.webhook = kinds.mkImage "quay.io/jetstack/cert-manager-webhook:v1.17.2";
            images.cainjector = kinds.mkImage "quay.io/jetstack/cert-manager-cainjector:v1.17.2";
            images.startupapicheck = kinds.mkImage "quay.io/jetstack/cert-manager-startupapicheck:v1.17.2";

            ready = kinds.readyDeployment {
              name = "cert-manager-webhook";
              namespace = inputs.namespace;
            };
          };

          bundles.issuers = kinds.mkBundle {
            needs = [ "cert-manager" ];

            externalSecrets = lib.optional fromLab "${caSecretNamespace}/${caSecretName}";

            resources =
              lib.optionalAttrs (!fromLab) {
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

            ready = kinds.readyCondition {
              resource = "clusterissuer/${inputs.issuerName}";
              condition = "Ready";
              namespace = inputs.namespace;
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
