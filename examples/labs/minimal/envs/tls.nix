# The minimal lab, serving https from a CA the lab mints itself.
#
# An environment is the same lab with different settings, which is exactly
# what this is: three more floes in the cluster and one input flipped.
# `minimal.local` stays plain HTTP, so the two run side by side and a change
# that breaks the untrusted path is still caught.
{
  lib,
  cataCharts,
  floes,
  config,
  ...
}:
{
  lab.name = "minimal.tls";

  # Its own subnet and its own k3d cluster name, so it can be up beside
  # `minimal.local` rather than fighting it for the network.
  lab.network.subnet = "172.25.0.0/16";

  # The host half: a resolver that answers for the zone, and an ingress that
  # terminates TLS with the CA `cert-generate` mints.
  lab.dns.enable = true;
  lab.proxy.enable = true;

  # There is an ingress now, so every route the clusters expose must answer
  # through it. This is the lab that proves the whole path.
  lab.verify.endpoints.enable = true;

  # `minimal.local` already claims 80/443 on loopback when both labs are up.
  lab.proxy.httpPort = 8080;
  lab.proxy.httpsPort = 8443;
  # 5356, not 5355: that one is LLMNR, which systemd-resolved holds.
  lab.dns.hostPort = 5356;
  lab.registry.port = 5051;
  lab.egress.port = 3129;

  lab.clusters.app.floes = {
    # So a pod resolves `*.minimal.test` too, not just the host.
    lab-dns = floes.lab-dns { };

    # One root, and the lab holds it. `cert-generate` writes the CA that
    # HAProxy serves from, and the CLI seeds it here as this issuer's backing
    # Secret — so cert-manager must not mint a second one over the top.
    cert-manager = lib.mkForce (
      floes.cert-manager {
        chart = "${cataCharts.cert-manager.chart}";
        rootFromLab = true;
      }
    );

    # trust-manager puts that CA in a ConfigMap in every namespace, so a
    # workload can verify a certificate the lab signed. It reads the Secret
    # through X509_ISSUANCE — the edge that used to point the other way.
    trust-manager = floes.trust-manager {
      chart = "${cataCharts.trust-manager.chart}";
    };

    gateway = lib.mkForce (
      floes.gateway {
        chart = "${cataCharts.traefik.chart}";
        tlsEnable = true;
      }
    );
  };
}
