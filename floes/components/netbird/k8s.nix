# The shapes this floe writes four of.
#
# Local to netbird rather than shared, deliberately. Every other floe in the
# set installs a chart or renders one or two resources by hand, and a helper
# hoisted to `lib/` for a single caller is an abstraction with no second case
# to keep it honest. netbird is the first floe with four workloads of its own,
# so the repetition is here and so is the answer to it.
{ lib, nb }:

let
  inherit (nb) namespace labels;
in
{
  serviceAccount = name: {
    apiVersion = "v1";
    kind = "ServiceAccount";
    metadata = {
      inherit name namespace labels;
    };
  };

  service =
    { name, ports }:
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        inherit name namespace labels;
      };
      spec = {
        type = "ClusterIP";
        selector."app.kubernetes.io/name" = name;
        ports = map (p: { protocol = "TCP"; } // p) ports;
      };
    };

  # A single-container Deployment with TCP probes on one port.
  #
  # `tcpSocket` and not a path: signal and relay speak gRPC and a websocket
  # protocol respectively, neither of which answers a plain GET, and the
  # dashboard's nginx would answer one before its config is in place. What
  # every one of them does mean is "the socket is open".
  deployment =
    {
      name,
      image,
      ports,
      probePort,
      args ? [ ],
      env ? [ ],
      volumeMounts ? [ ],
      volumes ? [ ],
      replicas ? 1,
    }:
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        inherit name namespace;
        labels = labels // {
          "app.kubernetes.io/name" = name;
        };
      };
      spec = {
        inherit replicas;
        selector.matchLabels."app.kubernetes.io/name" = name;
        template = {
          metadata.labels = labels // {
            "app.kubernetes.io/name" = name;
          };
          spec = {
            serviceAccountName = name;
            containers = [
              (
                {
                  inherit name image ports;
                  imagePullPolicy = "IfNotPresent";
                  livenessProbe.tcpSocket.port = probePort;
                  readinessProbe.tcpSocket.port = probePort;
                }
                // lib.optionalAttrs (args != [ ]) { inherit args; }
                // lib.optionalAttrs (env != [ ]) { inherit env; }
                // lib.optionalAttrs (volumeMounts != [ ]) { inherit volumeMounts; }
              )
            ];
          }
          // lib.optionalAttrs (volumes != [ ]) { inherit volumes; };
        };
      };
    };
}
