{
  lib,
  floe,
  sigs,
}:

let
  T = floe.T;

  stepType = (import ../steps { inherit lib; }).types;

  labStoreRecord = T.named "labStore" (
    T.record (
      removeAttrs sigs.LAB_STORE.fields [
        "name"
        "writable"
      ]
      // {
        direction = T.enum [
          "authored"
          "runtime"
        ];
      }
    )
  );

  labSecretRecord = T.named "labSecret" (
    T.record (
      removeAttrs sigs.LAB_SECRET.fields [
        "name"
        "readableKeys"
      ]
    )
  );
in
{
  labStores = floe.mkSig {
    name = "catallaxy.labStores";
    canonicalName = "labStores";
    description = "Every store the lab reads authored secret values from, keyed by the name the CLI knows it as.";
    fields = T.attrsOf labStoreRecord;
  };

  labSecrets = floe.mkSig {
    name = "catallaxy.labSecrets";
    canonicalName = "labSecrets";
    description = "Every secret the lab holds, keyed by the name the CLI knows it as.";
    fields = T.attrsOf labSecretRecord;
  };

  labServices = floe.mkSig {
    name = "catallaxy.labServices";
    canonicalName = "labServices";
    description = "Every host service the lab runs, keyed by the name the CLI knows it as.";
    fields = T.attrsOf (T.named "service" (T.record sigs.HOST_SERVICE.fields));
  };

  labSteps = floe.mkSig {
    name = "catallaxy.labSteps";
    canonicalName = "labSteps";
    description = "Every plan step the lab's floes contribute, keyed by step name.";

    fields = T.attrsOf (T.named "labStep" (T.moduleType stepType.declaredStepType));
  };

  dnsInfo = floe.mkSig {
    name = "catallaxy.dnsInfo";
    canonicalName = "dnsInfo";
    description = "Where the lab's resolver answers, as `cata lab dns` configures the host.";
    fields = T.named "dnsInfo" (
      T.record {
        host = T.str;
        port = T.port;
        zone = T.dnsName;

        tsigKeyname = T.str;
        tsigSecret = T.str;
        tsigSecretAlg = T.str;
      }
    );
  };

  routedHosts = floe.mkSig {
    name = "catallaxy.routedHosts";
    canonicalName = "routedHosts";
    description = "Hostnames the lab's ingress routes, keyed by the cluster that serves them.";
    fields = T.attrsOf (T.listOf T.dnsName);
  };

  cd = floe.mkSig {
    name = "catallaxy.cd";
    canonicalName = "cd";
    description = "How the lab's manifests reach its clusters, and the root Application that hands one over.";
    fields = T.record {
      bootstrap = T.str;
      git = T.attrsOf T.any;
      rootApplication = T.attrsOf T.any;

      perCluster = T.attrsOf (
        T.record {
          kind = T.str;
          waitTimeout = T.str;
        }
      );
    };
  };
}
