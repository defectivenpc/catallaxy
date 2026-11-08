{ lib, floe }:

let
  T = floe.T;
in
{
  REDIS_OPERATOR = floe.mkSig {
    name = "REDIS_OPERATOR";
    canonicalName = "redisOperator";
    description = "The Redis operator's CRDs are registered, so Redis CRs have a type.";
    fields = {
      crdKinds = (T.listOf T.str);
    };
  };
}
