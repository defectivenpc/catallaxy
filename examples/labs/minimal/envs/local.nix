# The local environment of the minimal lab.
#
# An environment is the same lab with different settings. Everything the lab
# declares with `mkDefault` is what an environment may change.
{ ... }:
{
  lab.name = "minimal.local";
  lab.network.subnet = "172.20.0.0/16";

  # The lab that proves PSA labelling works, because it is the fastest one
  # that runs. `enforce` is what the API server refuses below; `warn` is
  # left at the default `restricted`, so the run reports what raising it
  # would cost without refusing anything.
  lab.clusters.app.security.podSecurity.enable = true;

  # podinfo satisfies `restricted`, so it is held to it. cert-manager and
  # traefik are not, and stay at the cluster's `baseline`.
  lab.clusters.app.security.podSecurity.override.podinfo = "restricted";

  # The same lab proves the audit log, for the same reason: it is the one
  # that runs fastest. `Metadata` is the level that does not write Secret
  # contents to disk.
  lab.clusters.app.security.auditLogging.enable = true;
}
