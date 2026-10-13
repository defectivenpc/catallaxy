# secret-publication, alone.
#
# What it pins is the thing the lab options could not express: the key is an
# input, provided outward, and written down once. The address scheme that
# derived it from `(lab, cluster, namespace, secret)` on both sides is gone
# with the options, and so is every assertion that checked the two
# derivations agreed.
{
  lib,
  pkgs,
  floeCore,
}:

let
  support = import ./support.nix { inherit lib pkgs floeCore; };
  r = support.evalFloe {
    name = "secret-publication";
    inputs = {
      namespace = "cert-manager";
      secret = "lab-ca-ca-secret";
      key = "lab/core/lab-ca";
    };
  };

  push = r.bundles.publication.resources.push;
in
lib.runTests {

  # The key the consumer reads, as one value rather than a derivation each
  # side performs.
  testItPublishesTheKeyItWasGiven = {
    expr = r.provides.publication.key;
    expected = "lab/core/lab-ca";
  };

  # The store it pushed into travels too, because a consumer pointed at a
  # different backend is reading a store the key is not in.
  testItNamesTheStoreItPushedInto = {
    expr = r.provides.publication.storeName;
    expected = support.stubs.secretStore.value.storeName;
  };

  # The whole Secret as one value, which is what an empty `keys` means.
  testTheWholeSecretTravelsByDefault = {
    expr = push.spec.data;
    expected = [ { match.remoteRef.remoteKey = "lab/core/lab-ca"; } ];
  };

  testNamedKeysTravelOneByOne = {
    expr =
      (support.evalFloe {
        name = "secret-publication";
        inputs = {
          namespace = "cert-manager";
          secret = "lab-ca-ca-secret";
          key = "lab/core/lab-ca";
          keys = [ "tls.crt" ];
        };
      }).bundles.publication.resources.push.spec.data;
    expected = [
      {
        match = {
          secretKey = "tls.crt";
          remoteRef = {
            remoteKey = "lab/core/lab-ca";
            property = "tls.crt";
          };
        };
      }
    ];
  };

  # The push waits on the Secret existing. A PushSecret applied before the
  # thing it pushes reports healthy and writes nothing.
  testItWaitsForTheSecretItPushes = {
    expr = r.bundles.publication.needsSecrets;
    expected = [ "cert-manager/lab-ca-ca-secret" ];
  };

  # The store object is in this cluster, which is a hole rather than an
  # assertion: a ClusterSecretStore is not shared between clusters, only the
  # backend behind it is.
  testItRequiresAStoreHere = {
    expr =
      lib.attrNames
        (import ../components/secret-publication {
          inherit lib pkgs;
          catallaxy = support.catallaxy;
          inherit (support.catallaxy) floe sigs kinds;
        }).requires;
    expected = [
      "cluster"
      "secretStore"
    ];
  };
}
