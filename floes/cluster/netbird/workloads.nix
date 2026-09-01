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
        # What the relay tells peers to come back to. The routed name and the
        # path the gateway sends here, because a peer outside the cluster is
        # what a relay is for and it has no other way to reach this.
        {
          name = "NB_EXPOSED_ADDRESS";
          value = "${nb.apiDomain}/relay";
        }
        # The same secret management writes into its own config. A mismatch is
        # not a startup failure on either side — it is every relayed
        # connection being refused, which looks like a network problem.
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
        # Audience and client id are the same string for kanidm, and both are
        # read: one goes in the token request, the other is checked against
        # what comes back.
        {
          name = "AUTH_AUDIENCE";
          value = nb.oidc.clientId;
        }
        {
          name = "AUTH_CLIENT_ID";
          value = nb.oidc.clientId;
        }

        # The *client's* issuer, not the server's. A token minted for this
        # client carries the former, and the dashboard compares them.
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

        # The id token, not the access token. netbird's API validates the
        # audience, and only the id token carries the client as its audience.
        {
          name = "NETBIRD_TOKEN_SOURCE";
          value = "idToken";
        }

        # Both point at the routed API rather than the Service: this runs in
        # the visitor's browser.
        {
          name = "NETBIRD_MGMT_API_ENDPOINT";
          value = "https://${nb.apiDomain}";
        }
        {
          name = "NETBIRD_MGMT_GRPC_API_ENDPOINT";
          value = "https://${nb.apiDomain}";
        }

        # nginx runs unprivileged here and cannot write its default pid path.
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
