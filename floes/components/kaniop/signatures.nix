{ lib, floe }:

let
  T = floe.T;
in
{
  IDENTITY_OPERATOR = floe.mkSig {
    name = "IDENTITY_OPERATOR";
    canonicalName = "identityOperator";
    description = "The identity operator's CRDs are established, so its CRs can be applied.";
    fields = {
      crdsEstablished = T.str;
    };
  };
}
