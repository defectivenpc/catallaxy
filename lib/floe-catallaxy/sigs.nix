# Signatures for cluster-scope work: what a cluster offers its members, and
# what a gateway offers the workloads routing through it.
{ floe }:

let
  T = floe.T;
in
{
  # A cluster is an ordinary floe that happens to provide this. Members read
  # cluster facts through it rather than from an ambient option tree, so a
  # floe that touches one has said which.
  #
  # Every field is concrete. A manifest is rendered at build time, so a fact a
  # member interpolates has to be a decision (you choose the service CIDR) and
  # not a discovery.
  KUBERNETES_CLUSTER = floe.mkSig {
    name = "KUBERNETES_CLUSTER";
    fields = {
      name = T.k8sName;
      version = T.str;
      context = T.str;
      podSubnet = T.str;
      serviceSubnet = T.str;
    };
  };

  # Installed CRDs, as a signature.
  #
  # The shipped tree installs these through `cluster.prerequisites` rather
  # than from a floe, because gateway and cilium both need them and a bundle
  # declared twice is a conflicting definition rather than a merge — so the
  # cluster is made to own it and there is no owner left to disagree about.
  #
  # Exactly-one-provider is that rule already. Both floes require this; one
  # unit provides it; a second provider is a link error naming both. The
  # prerequisite mechanism has nothing left to do.
  GATEWAY_API = floe.mkSig {
    name = "GATEWAY_API";
    fields = {
      version = T.str;
      crdKinds = T.listOf T.str;
    };
  };

  # `parentRef` is the whole point: an HTTPRoute's attachment is a value the
  # gateway hands out, sealed to these three fields, rather than a hostname
  # and a namespace the consumer spells for itself off the gateway's options.
  API_GATEWAY = floe.mkSig {
    name = "API_GATEWAY";
    fields = {
      className = T.str;
      baseDomain = T.dnsName;
      parentRef = T.record {
        name = T.k8sName;
        namespace = T.k8sName;
        sectionName = T.str;
      };
    };
  };
}
