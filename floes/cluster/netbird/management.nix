# netbird's control plane: the API, the peer registry, and the config it runs
# from.
#
# Two of the values in that config are credentials the floe mints — the relay
# auth secret and the datastore encryption key — and neither may appear in a
# rendered manifest. So the ConfigMap carries a *template* with `@NAME@`
# placeholders, and an init container substitutes them into an in-memory
# volume before the server starts. That is the whole reason this floe has an
# init container at all.
{
  lib,
  k8s,
  nb,
}:

let
  inherit (nb)
    namespace
    labels
    managementHost
    signalHost
    apiDomain
    ;

  # The server's own config, as it will be on disk once the placeholders are
  # gone. Rendered to JSON here so the hash below covers it: the Deployment
  # carries a hash of this text, so a config change rolls the pods, which
  # nothing else would do — the ConfigMap is mounted and the server reads it
  # once at startup.
  managementConfig = {
    # STUN and TURN are the peer's problem, not the server's, and a lab on one
    # docker network needs neither: every peer can reach every other directly.
    # An earlier design carried options for both and the mesh lab set a TURN
    # domain it never stood a server up for.
    Stuns = [ ];
    TURNConfig = {
      Turns = [ ];
      CredentialsTTL = "12h";
      Secret = "secret";
      TimeBasedCredentials = false;
    };

    # `rels://` is the relay's own scheme for "websocket over TLS", and the
    # path is the one the gateway routes to the relay. Without it a peer
    # opens a websocket against the dashboard, which answers 404 and is
    # reported as the relay being unreachable.
    Relay = {
      Addresses = [ "rels://${apiDomain}/relay" ];
      CredentialsTTL = "24h";
      Secret = "@RELAY_AUTH_SECRET@";
    };

    StoreConfig.Engine = "sqlite";

    # The same host as everything else. Signal is told apart by its gRPC
    # path prefix, not by a name of its own.
    Signal = {
      Proto = "https";
      URI = "${apiDomain}:443";
      Username = "";
      Password = null;
    };

    # The gateway is the only thing in front of this, and it is inside the
    # cluster, so every peer address arrives as a forwarded one.
    ReverseProxy = {
      TrustedHTTPProxies = [ ];
      TrustedHTTPProxiesCount = 0;
      TrustedPeers = [ "0.0.0.0/0" ];
    };

    DisableDefaultPolicy = true;
    Datadir = "";
    DataStoreEncryptionKey = "@DATASTORE_ENC_KEY@";

    HttpConfig = {
      Address = "0.0.0.0:80";

      # The audience a token must carry, which for kanidm is the client id.
      AuthAudience = nb.oidc.clientId;
      AuthUserIDClaim = "sub";
      CertFile = "";
      CertKey = "";
      IdpSignKeyRefreshEnabled = true;

      # Keys by URL rather than a discovery document. Both work; this one
      # spells out what is fetched, and the discovery path adds a round trip
      # against a server that may not be up yet.
      AuthIssuer = nb.oidc.issuer;
      AuthKeysLocation = nb.oidc.jwksUri;
    };

    # netbird can drive an IdP's admin API to manage users. Pointing it at
    # kanidm would need a service account this platform does not mint yet, and
    # `none` is not a degraded mode: it means users arrive through their
    # tokens and netbird does not try to enumerate them.
    IdpManagerConfig = {
      ManagerType = "none";
      ClientConfig = {
        Issuer = "";
        TokenEndpoint = "";
        ClientID = "";
        ClientSecret = "";
        GrantType = "";
      };
      ExtraConfig = { };
      Auth0ClientCredentials = null;
      AzureClientCredentials = null;
      KeycloakClientCredentials = null;
      ZitadelClientCredentials = null;
    };

    # PKCE, not the device flow. The dashboard is a browser app and the client
    # is public, so there is no secret to protect a code exchange with — which
    # is exactly what PKCE replaces.
    DeviceAuthorizationFlow = null;

    PKCEAuthorizationFlow.ProviderConfig = {
      Audience = nb.oidc.clientId;
      ClientID = nb.oidc.clientId;
      ClientSecret = "";
      AuthorizationEndpoint = nb.oidc.authorizationEndpoint;
      TokenEndpoint = nb.oidc.tokenEndpoint;
      Domain = "";

      # `offline_access` is what gets a refresh token, without which the
      # dashboard logs you out whenever the access token expires.
      Scope = "openid profile email offline_access groups";
      UseIDToken = true;
      RedirectURLs = nb.callbackUrls;
      DisablePromptLogin = false;
      LoginFlag = 0;
    };
  };

  configJson = builtins.toJSON managementConfig;
in
{
  inherit configJson;

  resources = {
    netbird-management-sa = k8s.serviceAccount "netbird-management";

    netbird-management-pvc = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "netbird-management";
        inherit namespace;
        inherit labels;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = nb.storage;
      };
    };

    netbird-management-cm = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "netbird-management";
        inherit namespace;
        inherit labels;
      };
      data."management.tmpl.json" = configJson;
    };

    netbird-management-svc = k8s.service {
      name = "netbird-management";
      ports = [
        # h2c on both: the API is gRPC-Web over plain HTTP/2 and the peer
        # protocol is gRPC. Without the appProtocol the gateway downgrades to
        # HTTP/1.1 and every peer's registration hangs.
        {
          name = "http";
          port = 80;
          targetPort = "http";
          appProtocol = "kubernetes.io/h2c";
        }
        {
          name = "grpc";
          port = 33073;
          targetPort = "grpc";
          appProtocol = "kubernetes.io/h2c";
        }
      ];
    };

    netbird-management = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "netbird-management";
        inherit namespace;
        labels = labels // {
          "app.kubernetes.io/name" = "netbird-management";
        };
      };
      spec = {
        replicas = 1;

        # The PVC is ReadWriteOnce and sqlite tolerates exactly one writer, so
        # a rolling update that briefly runs two pods deadlocks on the volume.
        strategy.type = "Recreate";

        selector.matchLabels."app.kubernetes.io/name" = "netbird-management";
        template = {
          metadata = {
            labels = labels // {
              "app.kubernetes.io/name" = "netbird-management";
            };

            # The config is read once at startup out of a mounted ConfigMap,
            # so nothing would restart the server when it changes. This is
            # what does.
            annotations."catallaxy.io/config-hash" = builtins.substring 0 12 (
              builtins.hashString "sha256" configJson
            );
          };
          spec = {
            serviceAccountName = "netbird-management";

            initContainers = [
              {
                name = "render-config";
                image = nb.images.wait;
                command = [
                  "sh"
                  "-c"
                ];
                args = [
                  ''
                    set -eu
                    RELAY=$(cat /etc/netbird-secrets/RELAY_AUTH_SECRET)
                    DSEK=$(cat /etc/netbird-secrets/DATASTORE_ENC_KEY)
                    sed -e "s#@RELAY_AUTH_SECRET@#$RELAY#g" \
                        -e "s#@DATASTORE_ENC_KEY@#$DSEK#g" \
                        /tmp/netbird/management.tmpl.json \
                        > /etc/netbird/management.json
                  ''
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/netbird";
                  }
                  {
                    name = "config-template";
                    mountPath = "/tmp/netbird";
                  }
                  {
                    name = "relay-secret";
                    mountPath = "/etc/netbird-secrets/RELAY_AUTH_SECRET";
                    subPath = nb.relaySecretKey;
                    readOnly = true;
                  }
                  {
                    name = "datastore-key";
                    mountPath = "/etc/netbird-secrets/DATASTORE_ENC_KEY";
                    subPath = nb.datastoreKeyKey;
                    readOnly = true;
                  }
                ];
              }
            ];

            containers = [
              {
                name = "netbird-management";
                image = nb.images.management;
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--log-level"
                  "info"
                  "--log-file"
                  "console"
                  "--dns-domain"
                  apiDomain
                ];

                # Appended to the system roots, not replacing them. netbird
                # reaches public addresses too, and a container told to trust
                # only the lab CA stops trusting everything else.
                env = [
                  {
                    name = "SSL_CERT_DIR";
                    value = nb.caBundle.certDir;
                  }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 80;
                  }
                  {
                    name = "grpc";
                    containerPort = 33073;
                  }
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/netbird";
                  }
                  {
                    name = "management";
                    mountPath = "/var/lib/netbird";
                  }
                  {
                    name = nb.caBundle.volumeName;
                    mountPath = nb.caBundle.mountPath;
                    readOnly = true;
                  }
                ];
              }
            ];

            volumes = [
              # In memory, and never on disk: the rendered config holds both
              # credentials in clear.
              {
                name = "config";
                emptyDir.medium = "Memory";
              }
              {
                name = "config-template";
                configMap.name = "netbird-management";
              }
              {
                name = "management";
                persistentVolumeClaim.claimName = "netbird-management";
              }
              {
                name = "relay-secret";
                secret.secretName = nb.relaySecret;
              }
              {
                name = "datastore-key";
                secret.secretName = nb.datastoreKeySecret;
              }

              # trust-manager writes this ConfigMap into every namespace, so
              # it is here without netbird asking for it in particular — but
              # the *key* it lands under is the distributor's decision, which
              # is why it comes off the signature rather than being spelled.
              {
                name = nb.caBundle.volumeName;
                configMap = {
                  inherit (nb.caBundle) name;
                  items = [
                    {
                      inherit (nb.caBundle) key;
                      path = nb.caBundle.filename;
                    }
                  ];
                };
              }
            ];
          };
        };
      };
    };
  };

  inherit managementHost signalHost;
}
