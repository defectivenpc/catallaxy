{ lib, floe }:

let
  T = floe.T;
in
{
  METRICS_INGEST = floe.mkSig {
    name = "METRICS_INGEST";
    canonicalName = "metrics";

    behaviour = [ "scrapes-itself" ];
    description = "Where metrics are written and queried, and the monitoring CRDs a consumer may use.";
    fields = {
      crdsEstablished = T.str;
      crdKinds = (T.listOf T.str);
      queryUrl = T.str;
      remoteWriteUrl = T.str;
    };
  };

  LOG_INGEST = floe.mkSig {
    name = "LOG_INGEST";
    canonicalName = "logs";
    description = "Where logs are pushed and queried.";
    fields = {
      pushUrl = T.str;
      queryUrl = T.str;
      otlpUrl = T.str;
    };
  };

  TRACE_INGEST = floe.mkSig {
    name = "TRACE_INGEST";
    canonicalName = "traces";
    description = "Where traces are sent and queried.";
    fields = {
      queryUrl = T.str;
      otlpGrpc = T.str;
      otlpHttp = T.str;
    };
  };
}
