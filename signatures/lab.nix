{ lib, floe }:

let
  T = floe.T;

  stepType = (import ../steps { inherit lib; }).types;
in
{
  LAB_NETWORK = floe.mkSig {
    name = "LAB_NETWORK";
    canonicalName = "network";
    description = "The docker network a lab's containers share, and the gateway address on it.";
    fields = {
      name = T.str;
      subnet = T.str;

      gateway = T.str;
    };
  };

  OCI_MIRROR = floe.mkSig {
    name = "OCI_MIRROR";
    canonicalName = "ociMirror";
    description = "A pull-through cache on the operator's machine, as a cluster node reaches it.";
    fields = {
      name = T.str;
      port = T.port;
    };
  };

  LAB_STEPS = floe.mkSig {
    name = "LAB_STEPS";

    canonicalName = "step";
    description = "Plan steps a floe contributes, keyed by step name.";
    fields = {
      steps = T.attrsOf (T.named "authoredStep" (T.moduleType stepType.authoredStepType));
    };
  };

  HOST_RESOLVER = floe.mkSig {
    name = "HOST_RESOLVER";
    canonicalName = "resolver";
    description = "A resolver on the lab's network, as another container on it reaches it.";
    fields = {
      container = T.str;
    };
  };

  HOST_SERVICE = floe.mkSig {
    name = "HOST_SERVICE";
    canonicalName = "service";
    description = "A container the lab runs on the host, as `setup-services` starts it.";
    fields = {
      description = T.str;
      container = T.str;
      image = T.str;

      command = T.listOf T.str;
      ports = T.listOf T.str;
      networks = T.listOf T.str;

      dnsContainers = T.listOf T.str;

      volumes = T.attrsOf T.any;

      extraMounts = T.listOf (
        T.record {
          host = T.str;
          container = T.str;
        }
      );

      readyProbe = T.nullOr (T.attrsOf T.any);
    };
  };

  DNS_ZONE = floe.mkSig {
    name = "DNS_ZONE";
    canonicalName = "zone";
    description = "The lab's DNS zone and the server authoritative for it. The only fully portable signature.";
    fields = {
      zone = T.dnsName;

      server = T.str;
      port = T.port;
    };
  };
}
