# homelab, with a DNS controller publishing records into the lab's zone.
#
# The environment `external-dns` never had. Until now it was rendered only by
# `every-floe`, which is a fixture and never runs — and rendered there with a
# *generated* TSIG key, which cannot match the one Knot was configured with, so
# the one thing that would have failed was the one thing nothing tried.
#
# ## The awkward part, and why it is checked rather than hidden
#
# The controller authorises its RFC2136 updates with a TSIG key. The lab holds
# that key at `lab.dns.tsigSecret` and writes it into Knot's config; the floe
# takes a *reference* to a Secret in the cluster rather than the value,
# deliberately, because a key passed as a Helm value lands in the Deployment's
# argv and from there in the manifest, the digest that pins it, and the Nix
# store.
#
# So the value has to reach the cluster as a Secret, and a lab has only one
# way to do that: `lab.secrets.managed`, which reads from a store. This key is
# not in a store — it is a literal in the lab's own configuration, with a fixed
# default, because it authorises updates to a throwaway zone on loopback.
#
# The result is the same string in two places: `lab.dns.tsigSecret` and the env
# file below. That is a real wart and the fix is a way for a lab to project a
# value it already holds, which is a design question and not this file's
# business. What is not left to chance is the two agreeing —
# `lab-tsig-key-agrees` compares them, so the pair that would otherwise fail
# with a bare NOTAUTH at runtime fails at `nix flake check` instead.
{
  cataCharts,
  floes,
  config,
  ...
}:
{
  lab.name = "homelab.dns";

  # Its own everything, so it renders and runs beside `homelab.local` rather
  # than replacing it.
  lab.network.subnet = "172.35.0.0/16";
  lab.proxy.httpPort = 8085;
  lab.proxy.httpsPort = 8448;
  lab.dns.hostPort = 5361;
  lab.registry.port = 5057;
  lab.egress.port = 3134;

  lab.clusters.core.floes.external-dns = floes.external-dns {
    chart = "${cataCharts.external-dns.chart}";
    inherit (config.lab.dns) tsigKeyname tsigSecretAlg;

    tsigSecretRef = "external-dns/externaldns-tsig";

    # A k3d Service reports a cluster-internal LoadBalancer address nothing
    # outside the cluster can reach, so records point at the bridge gateway —
    # which is where the lab's ingress answers, and what the zone's wildcard
    # already says.
    defaultTargets = [ config.lab.network.gateway ];
  };

  # Authored, not generated: the value is Knot's, and a key this lab minted
  # for itself would authorise nothing.
  lab.secrets.stores.authored.backend = "env";
  lab.secrets.envFile = "examples/labs/homelab/envs/dns.env";

  lab.secrets.managed.externaldns-tsig = {
    store = "authored";
    keys.tsig-secret.generator = null;
  };

  lab.clusters.core.secrets.project.externaldns-tsig = {
    source = "externaldns-tsig";
    namespace = "external-dns";
    keys.tsig-secret.from = "tsig-secret";
  };
}
