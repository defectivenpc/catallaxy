{ lib, floe }:

let
  T = floe.T;
in
{
  POSTGRES_OPERATOR = floe.mkSig {
    name = "POSTGRES_OPERATOR";
    canonicalName = "postgresOperator";
    description = "The PostgreSQL operator's CRDs are registered, so a Cluster CR has a type.";
    fields = {
      crdKinds = (T.listOf T.str);
    };
  };
}
