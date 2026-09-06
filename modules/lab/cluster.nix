# One cluster: a set of instantiated floes, linked and elaborated.
#
# This is the seam between the two halves. Above it the module system merges
# partial configuration; below it the linker resolves signatures and the
# domain folds components into a cluster picture. The submodule does not
# reinterpret either — it links, elaborates, and lowers.
{
  lib,
  pkgs,
  catallaxy,
  cataCharts,
  k8sSpecs,
  floes,
  lab,
  scopeFor,
}:

let
  inherit (lib) mkOption types;

  coreKinds = (import ../../lib/kubernetes/types.nix { inherit lib; }).coreKinds;
  address = import ../../lib/eval/secret-address.nix { inherit lib; };
  infraLib = import ../../lib/render/infra.nix { inherit lib; };

  # A bundle the lab owns. Same shape as one a floe contributes, so it gets
  # the same derived edges and the same coherence checks.
  labBundle =
    {
      resources ? { },
      needsSecrets ? [ ],
    }:
    {
      inherit resources needsSecrets;
      helmCharts = { };
      yamls = [ ];
      createNamespaces = [ ];
      crds = [ ];
      secrets = [ ];
      externalSecrets = [ ];
      routedHosts = [ ];
      ready = null;
      awaitRollout = true;
      needs = [ ];
      declaredBy = "cluster";
      owner = {
        bootstrap = null;
        steady = null;
      };
      images = { };
      ops = { };
      lint = { };
      verify = { };
    };
in
types.submodule (
  { name, config, ... }:
  {
    options = {
      floes = mkOption {
        type = types.attrsOf types.raw;
        default = { };
        description = ''
          Instantiated floes, keyed by the name they link under. One of them
          must provide `KUBERNETES_CLUSTER`; the rest are what installs into
          it.

          Values are `.instantiate { ... }` results, not modules — a floe is
          an instance, and the linker resolves between instances.
        '';
      };

      colima = {
        enable = mkOption {
          type = types.bool;
          default = pkgs.stdenv.isDarwin;
          defaultText = lib.literalExpression "pkgs.stdenv.isDarwin";
          description = ''
            Run docker through a colima VM. A host fact rather than a cluster
            one, which is why it lives on the lab and not in the cluster floe.
          '';
        };
        profile = mkOption {
          type = types.str;
          default = "catallaxy";
          description = "Colima profile name.";
        };
        cpu = mkOption {
          type = types.ints.positive;
          default = 4;
          description = "vCPUs for the VM.";
        };
        memory = mkOption {
          type = types.ints.positive;
          default = 8;
          description = "GiB of RAM for the VM.";
        };
        disk = mkOption {
          type = types.ints.positive;
          default = 60;
          description = "GiB of disk for the VM.";
        };
      };

      waitTimeout = mkOption {
        type = types.str;
        default = "10m";
        description = "How long a bundle may take to reconcile before the apply gives up.";
      };

      # Where this cluster's edge is — RFC 0005 §6.4.
      #
      # Every field is read off the descriptor the provisioner emitted,
      # because where a cluster's edge is follows from how it was made and
      # not from what is installed in it. It stays an option surface so a lab
      # can override one, which is the case a fixture needs and nothing in
      # the shipped tree does.
      #
      # This used to be `ingress`, defaulting `backend` by testing
      # `provisioner == "k3d"` and building the container name here — so
      # every new provisioner was an edit to the lab, which is the one thing
      # RFC 0005 §8.2 says adding one must not be.
      edge =
        let
          fromDescriptor = (lib.head (lib.attrValues config.out.cluster)).edge;
        in
        {
          mode = mkOption {
            type = types.enum [
              "proxy"
              "self"
              "none"
            ];
            default = fromDescriptor.mode;
            defaultText = lib.literalExpression "what the provisioner answered";
            description = ''
              Who fronts this cluster.

              `proxy` — the lab does, at `backend`. `self` — the cluster is
              its own edge and the lab routes nothing to it, which is what a
              managed cluster in a cloud answers. `none` — nothing routes to
              it at all.

              `self` is a refusal to route rather than a deferred address:
              the lab has nothing to say about how to reach the cluster, and
              saying nothing is a complete answer.
            '';
          };

          backend = mkOption {
            type = types.nullOr types.str;

            # Keyed on the *effective* mode, not the descriptor's. A lab that
            # overrides the mode is saying something else reaches this
            # cluster, and leaving the provisioner's backend standing would
            # have the document assert a route the proxy does not render.
            default = if config.edge.mode == "proxy" then fromDescriptor.backend else null;
            defaultText = lib.literalExpression "the backend the provisioner named, when the lab is this cluster's edge";
            description = ''
              Hostname the lab's proxy connects to for this cluster, resolved
              on the lab's docker network.

              Null unless `mode` is `proxy`. A cluster the lab fronts and
              cannot name a backend for is refused, rather than rendering a
              route to a name that resolves to nothing and timing out every
              request through it.
            '';
          };

          httpPort = mkOption {
            type = types.port;
            default = fromDescriptor.httpPort;
            defaultText = lib.literalExpression "what the provisioner answered";
            description = "Port the proxy dials for plain HTTP, at the backend.";
          };

          httpsPort = mkOption {
            type = types.port;
            default = fromDescriptor.httpsPort;
            defaultText = lib.literalExpression "what the provisioner answered";
            description = "Port the proxy dials for HTTPS, at the backend.";
          };
        };

      # Lab-held material landed in this cluster as a Secret.
      #
      # The Secret is rendered and applied by `cata` from the decrypted store,
      # not by Nix, so no value passes through evaluation and none reaches the
      # store path. What the cluster contributes is the *position*: each
      # projection becomes a zero-resource bundle providing
      # `secret:<ns>/<name>`, so a bundle that reads one waits for it through
      # the ordinary graph without knowing the CLI is what supplies it.
      secrets.project = mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                source = mkOption {
                  type = types.str;
                  description = "Which `lab.secrets.managed` entry supplies the values.";
                };

                namespace = mkOption {
                  type = types.str;
                  default = "default";
                  description = "Namespace the Secret lands in.";
                };

                keys = mkOption {
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        from = mkOption {
                          type = types.str;
                          description = "Key in the managed secret this one is taken from.";
                        };
                        transform = mkOption {
                          type = types.enum [
                            "none"
                            "base64"
                            "json-wrap"
                          ];
                          default = "none";
                          description = "How the value is encoded on the way in.";
                        };
                        jsonKey = mkOption {
                          type = types.nullOr types.str;
                          default = null;
                          description = "Key name inside the object, for `json-wrap`.";
                        };
                      };
                    }
                  );
                  default = { };
                  description = "Which keys to project, and under what names.";
                };
              };
            }
          )
        );
        default = { };
        description = "Secrets projected into this cluster from the lab's stores.";
      };

      # Secrets this cluster mints at runtime and makes available to the rest
      # of the lab. A value that exists before the lab does does not belong
      # here — author it in a store and project it into each cluster that
      # needs it. This is for values only the running lab can produce.
      secrets.publish = mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                namespace = mkOption {
                  type = types.str;
                  description = "Namespace holding the Secret to publish.";
                };

                secret = mkOption {
                  type = types.str;
                  default = name;
                  defaultText = lib.literalExpression "the attribute name";
                  description = "The local Secret whose value is pushed.";
                };

                keys = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = ''
                    Which keys to push. Empty publishes the Secret whole,
                    which is what you want for a credential minted as one
                    thing.
                  '';
                };

                store = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Which `lab.secrets.stores` entry to push into.";
                };
              };
            }
          )
        );
        default = { };
        description = "Runtime values this cluster shares with the rest of the lab.";
      };

      # The producing cluster is named, never asked. Both sides derive the
      # same address from the producer's identity, so nothing is negotiated
      # and a publisher never learns who reads it.
      secrets.subscribe = mkOption {
        type = types.attrsOf (
          types.submodule (
            { name, ... }:
            {
              options = {
                from = mkOption {
                  type = types.str;
                  description = "The cluster in this lab that publishes it.";
                };

                namespace = mkOption {
                  type = types.str;
                  description = "Namespace the Secret should land in here.";
                };

                secret = mkOption {
                  type = types.str;
                  default = name;
                  defaultText = lib.literalExpression "the attribute name";
                  description = "What to call the Secret locally.";
                };

                refreshInterval = mkOption {
                  type = types.str;
                  default = "1h";
                  description = "How often to re-read the store.";
                };

                store = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Which `lab.secrets.stores` entry to read from.";
                };

                labels = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = ''
                    Labels on the materialised Secret.

                    What reads a Secret often finds it by label rather than by
                    name — argocd treats one labelled
                    `argocd.argoproj.io/secret-type: repository` as a
                    repository registration. Without this a subscriber can
                    receive the value and have nothing notice it arrived.
                  '';
                };

                annotations = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = "Annotations on the materialised Secret.";
                };

                fields = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  example = {
                    password = "{{ .token }}";
                    username = "admin";
                  };
                  description = ''
                    Rewrite the published keys on the way in.

                    A credential arrives as whatever the minting cluster
                    called it, and the consumer usually wants it under a
                    different name beside some constants: a token becomes
                    `password`, next to the `url` and `username` that identify
                    what it opens. `{{ .<key> }}` reads a published key;
                    anything else is literal. Empty materialises the published
                    keys unchanged.
                  '';
                };
              };
            }
          )
        );
        default = { };
        description = "Runtime values this cluster reads from another cluster in the lab.";
      };

      provides = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "netbird/mesh" ];
        description = ''
          Promises this cluster offers to the lab, as `<unit>/<provide>`.

          A link is per-cluster, so `requires.mesh = MESH_NETWORK` finds only
          what is in the same cluster — right for almost everything, and wrong
          for the few things a lab has one of. Naming a promise here puts it
          in the lab's scope, where every *other* cluster resolves it if
          nothing of its own answers first.

          Nearer wins, so offering something lab-wide cannot break a cluster
          that already has its own: a cluster with a gateway keeps it, and one
          without picks up the lab's.

          Per promise rather than per unit, because one floe holds both kinds.
          `netbird` provides `MESH_NETWORK`, which is the whole point of a
          mesh, and `MESH_ADMIN`, which is a reference to a Secret in this
          cluster and can never mean anything anywhere else — offering the
          unit would offer both, and `link` is right to refuse the second.

          Opt-in rather than automatic, for the same reason: a cluster's floes
          promise plenty that is meaningless elsewhere. What is *readable*
          across the boundary is then decided per field by `T.local`; see
          `lib/floe-core/link.nix`.
        '';
      };

      assertions = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = ''
          Config-validity checks scoped to this cluster, including every one
          its floes declared. `lib/lab.nix` reads these and throws, so a
          violated assertion fails `nix eval` rather than reaching a cluster.
        '';
      };

      warnings = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Soft advisories from this cluster's floes, already prefixed with the
          floe that raised them. Carried into `metadata.json` rather than
          failing evaluation.
        '';
      };

      link = mkOption {
        type = types.raw;
        internal = true;
        readOnly = true;
        description = "The link result: provides, out, graph, phases, wiring.";
      };

      stacks = mkOption {
        type = types.attrsOf types.raw;
        readOnly = true;
        internal = true;
        description = ''
          This cluster's provisioning stacks, keyed `(unit, phase)` and
          scoped by the cluster — RFC 0003 §5. Read by the lab, which renders
          each one and derives the plan steps that drive it.
        '';
      };

      out = mkOption {
        type = types.raw;
        internal = true;
        readOnly = true;
        description = "The elaborated cluster picture: bundles, waves, namespaces, and the rest.";
      };

      manifests = mkOption {
        type = types.package;
        internal = true;
        readOnly = true;
        description = "The rendered wave tree for this cluster.";
      };

      spec = mkOption {
        type = types.attrs;
        internal = true;
        readOnly = true;
        description = "`ClusterSpec` as the CLI parses it.";
      };
    };

    config =
      let
        # ---- the enclosing scope ------------------------------------------
        #
        # What the lab offers this cluster: everything it provides itself,
        # plus what every *other* cluster offered upward.
        #
        # Our own contributions are excluded, and that is what breaks the
        # evaluation cycle rather than a resolution rule — a cluster that both
        # offers and consumes would otherwise depend on its own link result.
        # Resolution would not need it: nearer-wins means a local unit answers
        # first anyway.
        #
        # Reading a sibling cluster is the move `publicationFor` below already
        # makes, and terminates for the same reason: a producer's link never
        # reads a consumer's.
        scope = scopeFor name;

        # ---- cross-cluster secret sharing ----------------------------------

        # The SECRET_STORE provides in this cluster, read off the instantiated
        # floes. The signature name is on the definition, so this asks what a
        # floe promised rather than guessing from what it rendered.
        storesHere = lib.concatLists (
          lib.mapAttrsToList (
            unit: inst:
            lib.mapAttrsToList (instName: _: config.link.provides.${unit}.${instName}) (
              lib.filterAttrs (_: sig: sig.name == "SECRET_STORE") inst.def.provides
            )
          ) config.floes
        );

        storeNamesHere = map (s: s.storeName) storesHere;

        # A lab store with exactly one runtime backend is what an entry defaults
        # to. More than one and there is nothing to default to; none and there
        # is nothing to share through.
        runtimeStores = lib.attrNames (lib.filterAttrs (_: s: s.direction == "runtime") lab.secrets.stores);

        storeOf = entry: if entry.store != null then entry.store else lib.head runtimeStores;
        hasDefault = lib.length runtimeStores == 1;
        resolvable = entry: entry.store != null || hasDefault;

        addressOf =
          { cluster, publication }:
          address.remoteKey {
            lab = lab.name;
            inherit cluster;
            inherit (publication) namespace secret;
          };

        # A subscriber reads the producer's own declaration rather than
        # restating its namespace and Secret name, so the two cannot drift.
        # Safe to read a sibling: `secrets.publish` is a plain option with a
        # default and is not gated on any floe, so this cannot cycle.
        # Keyed on the *attribute name*, which is the contract between the two
        # clusters. `secret` on either side is only what the value is called
        # locally — the producer's own Secret, and the name the consumer wants
        # it under — and neither is a name the other should have to know.
        publicationFor = subName: sub: (lab.clusters.${sub.from}.secrets.publish or { }).${subName} or null;

        pushDataFor =
          pub: remoteKey:
          if pub.keys == [ ] then
            [ { match.remoteRef.remoteKey = remoteKey; } ]
          else
            map (k: {
              match = {
                secretKey = k;
                remoteRef = {
                  inherit remoteKey;
                  property = k;
                };
              };
            }) pub.keys;

        publicationBundles = lib.mapAttrs' (
          pubName: pub:
          lib.nameValuePair "secret-publication/${pubName}" (labBundle {
            resources.push = {
              apiVersion = "external-secrets.io/v1alpha1";
              kind = "PushSecret";
              metadata = {
                name = "push-${pubName}";
                inherit (pub) namespace;
              };
              spec = {
                updatePolicy = "Replace";
                deletionPolicy = "Delete";
                secretStoreRefs = [
                  {
                    name = address.storeResourceName (storeOf pub);
                    kind = "ClusterSecretStore";
                  }
                ];
                selector.secret.name = pub.secret;
                data = pushDataFor pub (addressOf {
                  cluster = name;
                  publication = pub;
                });
              };
            };
          })
        ) (lib.filterAttrs (_: resolvable) config.secrets.publish);

        subscriptionBundles =
          lib.mapAttrs'
            (
              subName: sub:
              lib.nameValuePair "secret-subscription/${subName}" (labBundle {
                resources.pull = {
                  apiVersion = "external-secrets.io/v1beta1";
                  kind = "ExternalSecret";
                  metadata = {
                    name = "subscribe-${subName}";
                    inherit (sub) namespace;
                  };
                  spec = {
                    inherit (sub) refreshInterval;
                    secretStoreRef = {
                      name = address.storeResourceName (storeOf sub);
                      kind = "ClusterSecretStore";
                    };
                    target = {
                      name = sub.secret;
                      creationPolicy = "Owner";
                    }
                    // lib.optionalAttrs (sub.fields != { } || sub.labels != { } || sub.annotations != { }) {
                      template = {
                        engineVersion = "v2";
                        metadata = {
                          inherit (sub) labels annotations;
                        };
                      }
                      // lib.optionalAttrs (sub.fields != { }) { data = sub.fields; };
                    };
                    dataFrom = [
                      {
                        extract.key = addressOf {
                          cluster = sub.from;
                          publication = publicationFor subName sub;
                        };
                      }
                    ];
                  };
                };
              })
            )
            (
              lib.filterAttrs (
                n: s: resolvable s && (lab.clusters ? ${s.from}) && publicationFor n s != null
              ) config.secrets.subscribe
            );

        sharingEntries =
          lib.mapAttrsToList (n: v: {
            what = "publish";
            name = n;
            entry = v;
          }) config.secrets.publish
          ++ lib.mapAttrsToList (n: v: {
            what = "subscribe";
            name = n;
            entry = v;
          }) config.secrets.subscribe;

        sharingAssertions =
          # Which store, when there is no obvious one.
          lib.concatMap (
            e:
            lib.optional (!(resolvable e.entry)) {
              assertion = false;
              message =
                "secrets.${e.what}.${e.name} names no store, and this lab has "
                + (
                  if runtimeStores == [ ] then
                    "no runtime store to default to. Declare one: a store whose backend is `vault` or `external`."
                  else
                    "${toString (lib.length runtimeStores)} of them (${lib.concatStringsSep ", " runtimeStores}), so there is nothing to default to. Set `store`."
                );
            }
          ) sharingEntries

          # An authored store is read-only and top-down. Sharing a value the lab
          # mints at runtime needs one a cluster may write back into.
          ++ lib.concatMap (
            e:
            let
              s = storeOf e.entry;
            in
            lib.optionals (resolvable e.entry) (
              if !(lab.secrets.stores ? ${s}) then
                [
                  {
                    assertion = false;
                    message =
                      "secrets.${e.what}.${e.name}.store is '${s}', which is not a declared store "
                      + "(${lib.concatStringsSep ", " (lib.attrNames lab.secrets.stores)}).";
                  }
                ]
              else
                [
                  {
                    assertion = lab.secrets.stores.${s}.direction == "runtime";
                    message =
                      "secrets.${e.what}.${e.name} uses store '${s}', whose backend is "
                      + "'${lab.secrets.stores.${s}.backend}' and so authored. An authored store is "
                      + "read-only and top-down: you write the value and it is projected into every "
                      + "cluster that needs it, and a cluster cannot write back. Sharing a value the "
                      + "lab mints at runtime needs a `runtime` store — one backed by `vault` or "
                      + "`external`. If this value exists before the lab does, declare it in "
                      + "`lab.secrets.managed` and use `secrets.project` instead.";
                  }

                  # The store object has to be in *this* cluster: a
                  # `ClusterSecretStore` is not shared between clusters, only
                  # the backend behind it is.
                  {
                    assertion = lib.elem (address.storeResourceName s) storeNamesHere;
                    message =
                      "secrets.${e.what}.${e.name} uses store '${s}', but cluster '${name}' has no "
                      + "floe providing SECRET_STORE named '${address.storeResourceName s}'. The "
                      + "PushSecret and ExternalSecret resources name a ClusterSecretStore in the "
                      + "cluster they are applied to, and one that is not there is admitted and then "
                      + "never reconciles. Add `floes.secret-store { labStore = \"${s}\"; ... }`.";
                  }
                ]
            )
          ) sharingEntries

          # The handshake. Both sides derive the same address from the
          # producer's identity, so a name that does not match on both sides
          # leaves the ExternalSecret waiting forever on a key nothing wrote.
          # Checking it here is the point of naming the producer rather than
          # asking it.
          ++ lib.concatLists (
            lib.mapAttrsToList (
              subName: sub:
              if !(lab.clusters ? ${sub.from}) then
                [
                  {
                    assertion = false;
                    message =
                      "secrets.subscribe.${subName}.from is '${sub.from}', which is not a cluster in "
                      + "this lab (${lib.concatStringsSep ", " (lib.attrNames lab.clusters)}).";
                  }
                ]
              else
                [
                  {
                    assertion = publicationFor subName sub != null;
                    message =
                      "secrets.subscribe.${subName} reads from cluster '${sub.from}', which does not "
                      + "publish '${subName}'. It publishes: "
                      + "${
                        lib.concatStringsSep ", " (lib.attrNames (lab.clusters.${sub.from}.secrets.publish or { }))
                      }. Both sides derive the same address from the producer's identity, so a name "
                      + "that does not match on both leaves the ExternalSecret waiting forever on a "
                      + "key nothing wrote.";
                  }
                ]
            ) config.secrets.subscribe
          );
      in
      {
        link = catallaxy.floe.link {
          units = config.floes;
          inherit scope;
          policies = [
            catallaxy.policies.oneCluster
            catallaxy.policies.componentsTargetTheCluster
            catallaxy.policies.needsNameSiblings
            catallaxy.policies.backsNameOwnBundles
            catallaxy.policies.kanidmPrincipalsAreUnique
            catallaxy.policies.promisedHostsAreRouted
          ];
        };

        out = catallaxy.elaborateCluster {
          linkResult = config.link;
          inherit coreKinds;
          # The attribute name *is* the Secret's name: `inject_projections`
          # renders `metadata.name` from it, so a separate option for it would
          # be a field the CLI ignores.
          projectedSecrets = lib.mapAttrs (_: p: p.namespace) config.secrets.project;

          extraBundles = publicationBundles // subscriptionBundles;
        };

        # The stacks this cluster's floes declare, keyed `(unit, phase)`.
        #
        # Scoped by the cluster name so two clusters running the same floe get
        # two state files rather than one whose addresses collide — the same
        # reason RFC 0003 §5 keys on the instantiation and not the definition.
        stacks = infraLib.collectStacks {
          scope = name;
          inherit (config.out) resources publications;
        };

        # Every assertion the cluster's floes made, already prefixed with the
        # floe that made it by the join, plus the lab's own wiring checks.
        #
        # The sharing bundles above are filtered to the entries that resolve, so
        # a misconfigured one reports its own problem rather than rendering a
        # resource that names nothing and failing much later.
        assertions = config.out.assertions ++ sharingAssertions;
        warnings = config.out.warnings;

        manifests = catallaxy.renderCluster {
          inherit name;
          owner = lab.name;
          cluster = config.out;
          inherit (config) waitTimeout;
        };

        # `catallaxy.cluster` already tracks `ClusterSpec`'s field names, so
        # this is a merge rather than a translation: the floe answers what a
        # cluster knows about itself, and the lab adds what only a lab knows.
        spec =
          let
            descriptor = lib.head (lib.attrValues config.out.cluster);

            # The union's key *is* the provisioner. Reading it here rather
            # than taking a second field off the descriptor is what stops the
            # tag and the block disagreeing — a spec saying `talos` while
            # carrying k3d settings would type-check and mean nothing.
            provisioner = lib.head (lib.attrNames descriptor.config);

            # What only the lab knows, per variant. One entry today; a
            # provisioner with nothing to add needs no entry, and this is the
            # place to look when one does.
            #
            # The k3d floe leaves `network` null because which docker network
            # a cluster joins is a fact about what else is on the host.
            # `docker-network-create` makes this one first.
            labKnows = {
              k3d = c: c // { network = lab.name; };

              # talosctl makes the cluster's own network and will not join
              # one it did not make, and kube-proxy in nftables mode will not
              # answer a NodePort on an interface added afterwards — so
              # putting the nodes on the lab's bridge as well looks right and
              # still refuses every connection. Reaching in is the direction
              # that works, and the proxy is what has to reach.
              talos =
                c:
                c
                // {
                  reachableFrom = lib.optional lab.proxy.enable lab.proxy.containerName;
                };
            };
          in
          {
            inherit (descriptor)
              name
              provider
              kubeContext
              kubernetes
              network
              ;

            inherit provisioner;

            # Carried to the CLI because `verify` has to know which hostnames
            # it can reach through the lab's proxy. It used to resolve every
            # routed host to loopback, which is right exactly when the lab is
            # the edge for every cluster — true until one is not.
            inherit (config) edge;

            labName = lab.name;

            deploy.strategy = "kapp";
            lifecycle = { };

            # `ProvisionerConfig` in `cli/src/domain/cluster.rs` is an
            # externally-tagged enum, which is exactly this shape: one key,
            # named for the variant. A provisioner that is not built yet is
            # absent rather than empty, and absent is a parse error naming the
            # variant instead of a default that silently means k3d.
            provisionerConfig = {
              ${provisioner} = (labKnows.${provisioner} or lib.id) descriptor.config.${provisioner};
            };

            # Host facts, off the provisioner config where they never
            # belonged: colima is a macOS VM the operator runs and the wait is
            # how long *this lab* is willing to spend, neither of which is
            # something k3d is told. `docker.clusterName` went with them — it
            # was read by nothing at all.
            host = {
              inherit (config) waitTimeout;
              colima = {
                inherit (config.colima)
                  enable
                  profile
                  cpu
                  memory
                  disk
                  ;
              };
            };

            # The CLI knows a floe only as a name and whether it is on. That is
            # the whole of `FloeSpec`, and the linker has already refused any
            # floe that should not be here.
            floes = lib.mapAttrs (_: _: { enable = true; }) config.floes;

            inherit (config.out) exposedHosts;

            # Stack names only. The rendered stacks live in the lab package
            # and the plan steps name them; a spec carrying the resources
            # themselves would put every provider argument into the document
            # every `nix eval` of the lab has to serialise.
            infraStacks = lib.attrNames config.stacks;

            # `ProjectionConfig` in `cli/src/domain/cluster.rs`. `source`,
            # `namespace` and every key's `from` are required there; the field
            # was a bare `Value` once, decoded by something that warned and
            # returned nothing on failure, so a misconfigured projection
            # produced no Secret and no error.
            projections = lib.mapAttrs (_: p: {
              inherit (p) source namespace;
              keys = lib.mapAttrs (_: k: {
                inherit (k) from transform jsonKey;
              }) p.keys;
            }) config.secrets.project;

            # `cata lab plan-manifests` reads this to show the install order
            # without building anything. Three fields, not the wave entries
            # themselves: an entry carries every resource in its bundle, and
            # passing those through would put the whole rendered cluster inside
            # the lab document that every `nix eval` of it has to serialise.
            manifestWaves = map (
              wave:
              map (b: {
                inherit (b) name hasReadyProbe resourceCount;
              }) wave
            ) config.out.waves;
          };
      };
  }
)
