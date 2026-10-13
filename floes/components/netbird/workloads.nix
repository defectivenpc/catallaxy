# The three workloads with no configuration to speak of: signal, relay, and
# the dashboard.
#
# Signal brokers the WireGuard handshake between two peers and holds no state.
# The relay carries traffic for a pair that cannot reach each other directly,
# and shares one secret with management so it can validate what management
# issued. The dashboard is a static bundle configured entirely by environment.
{
  lib,
  k8s,
  nb,
}:

let
  inherit (nb) namespace labels;

  # Signal speaks the current protocol on 80 and the pre-0.26 one on 10000.
  # Both, because a peer built against either has to be able to register — and
  # netbird's own charts still publish the legacy port.
  signalPort = 80;
  signalLegacyPort = 10000;

  relayPort = 33080;
in
{
  signal = {
    netbird-signal-sa = k8s.serviceAccount "netbird-signal";

    netbird-signal-svc = k8s.service {
      name = "netbird-signal";
      ports = [
        {
          name = "http";
          port = signalPort;
          targetPort = "http";
          appProtocol = "kubernetes.io/h2c";
        }
        {
          name = "grpc-compat";
          port = signalLegacyPort;
          targetPort = signalLegacyPort;
          appProtocol = "kubernetes.io/h2c";
        }
      ];
    };

    netbird-signal = k8s.deployment {
      name = "netbird-signal";
      image = nb.images.signal;
      args = [
        "--port"
        (toString signalPort)
        "--log-level"
        "info"
        "--log-file"
        "console"
      ];
      ports = [
        {
          name = "http";
          containerPort = signalPort;
        }
        {
          name = "grpc-compat";
          containerPort = signalLegacyPort;
        }
      ];
      probePort = "http";
    };
  };

  relay = {
    netbird-relay-sa = k8s.serviceAccount "netbird-relay";

    netbird-relay-svc = k8s.service {
      name = "netbird-relay";
      ports = [
        {
          name = "http";
          port = relayPort;
          targetPort = "ws";
        }
      ];
    };

    netbird-relay = k8s.deployment {
      name = "netbird-relay";
      image = nb.images.relay;
      args = [
        "--log-file"
        "console"
      ];
      env = [
        {
          name = "NB_LOG_LEVEL";
          value = "info";
        }
        {
          name = "NB_LISTEN_ADDRESS";
          value = ":${toString relayPort}";
        }
        {
          name = "NB_EXPOSED_ADDRESS";
          value = "${nb.apiDomain}/relay";
        }
        {
          name = "NB_AUTH_SECRET";
          valueFrom.secretKeyRef = {
            name = nb.relaySecret;
            key = nb.relaySecretKey;
          };
        }
      ];
      ports = [
        {
          name = "ws";
          containerPort = relayPort;
        }
      ];
      probePort = "ws";
    };
  };

  dashboard = {
    netbird-dashboard-sa = k8s.serviceAccount "netbird-dashboard";

    netbird-dashboard-svc = k8s.service {
      name = "netbird-dashboard";
      ports = [
        {
          name = "http";
          port = 80;
          targetPort = "http";
        }
      ];
    };

    netbird-dashboard = k8s.deployment {
      name = "netbird-dashboard";
      image = nb.images.dashboard;
      env = [
        {
          name = "AUTH_AUDIENCE";
          value = nb.oidc.clientId;
        }
        {
          name = "AUTH_CLIENT_ID";
          value = nb.oidc.clientId;
        }

        {
          name = "AUTH_AUTHORITY";
          value = nb.oidc.issuer;
        }
        {
          name = "USE_AUTH0";
          value = "false";
        }
        {
          name = "AUTH_SUPPORTED_SCOPES";
          value = "openid profile email offline_access groups";
        }
        {
          name = "AUTH_REDIRECT_URI";
          value = "/peers";
        }
        {
          name = "AUTH_SILENT_REDIRECT_URI";
          value = "/add-peers";
        }

        {
          name = "NETBIRD_TOKEN_SOURCE";
          value = "idToken";
        }

        {
          name = "NETBIRD_MGMT_API_ENDPOINT";
          value = "https://${nb.apiDomain}";
        }
        {
          name = "NETBIRD_MGMT_GRPC_API_ENDPOINT";
          value = "https://${nb.apiDomain}";
        }

        {
          name = "NGINX_PID";
          value = "/tmp/nginx.pid";
        }
      ];
      ports = [
        {
          name = "http";
          containerPort = 80;
        }
      ];
      probePort = "http";
      volumeMounts = [
        {
          name = "tmp";
          mountPath = "/tmp";
        }
      ];
      volumes = [
        {
          name = "tmp";
          emptyDir = { };
        }
      ];
    };
  };
}
