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
    Stuns = [ ];
    TURNConfig = {
      Turns = [ ];
      CredentialsTTL = "12h";
      Secret = "secret";
      TimeBasedCredentials = false;
    };

    Relay = {
      Addresses = [ "rels://${apiDomain}/relay" ];
      CredentialsTTL = "24h";
      Secret = "@RELAY_AUTH_SECRET@";
    };

    StoreConfig.Engine = "sqlite";

    Signal = {
      Proto = "https";
      URI = "${apiDomain}:443";
      Username = "";
      Password = null;
    };

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

      AuthAudience = nb.oidc.clientId;
      AuthUserIDClaim = "sub";
      CertFile = "";
      CertKey = "";
      IdpSignKeyRefreshEnabled = true;

      AuthIssuer = nb.oidc.issuer;
      AuthKeysLocation = nb.oidc.jwksUri;
    };

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

    DeviceAuthorizationFlow = null;

    PKCEAuthorizationFlow.ProviderConfig = {
      Audience = nb.oidc.clientId;
      ClientID = nb.oidc.clientId;
      ClientSecret = "";
      AuthorizationEndpoint = nb.oidc.authorizationEndpoint;
      TokenEndpoint = nb.oidc.tokenEndpoint;
      Domain = "";

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

        strategy.type = "Recreate";

        selector.matchLabels."app.kubernetes.io/name" = "netbird-management";
        template = {
          metadata = {
            labels = labels // {
              "app.kubernetes.io/name" = "netbird-management";
            };

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
