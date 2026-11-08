{ lib, floe }:

let
  T = floe.T;
in
{
  MESH_OPERATOR = floe.mkSig {
    mayExport = false;
    name = "MESH_OPERATOR";
    canonicalName = "meshOperator";
    description = "The mesh operator's CRDs are registered, and the router its resources attach to.";
    fields = {
      namespace = T.k8sName;
      crdKinds = (T.listOf T.str);

      routerRef = (
        T.nullOr (
          T.record {
            name = T.k8sName;
            namespace = T.k8sName;
          }
        )
      );
    };
  };
}
