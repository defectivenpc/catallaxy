{ lib, floe }:

let
  T = floe.T;
in
{
  X509_WEBHOOK = floe.mkSig {
    name = "X509_WEBHOOK";
    canonicalName = "webhook";
    description = "The certificate controller's admission webhook is serving, so its CRs are accepted.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);
    };
  };
}
