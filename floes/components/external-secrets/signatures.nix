{ lib, floe }:

let
  T = floe.T;
in
{
  SECRET_GENERATION = floe.mkSig {
    name = "SECRET_GENERATION";
    canonicalName = "generation";
    description = "A controller that mints secret values in the cluster, so none is rendered into a manifest.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);

      generatorApiVersion = T.str;
    };
  };
}
