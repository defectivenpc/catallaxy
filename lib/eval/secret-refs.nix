# Which Secrets a resource creates, and which it reads.
#
# Both halves are needed and they are not symmetric. A `Certificate` names a
# Secret in `spec.secretName` and *creates* it; a Pod names one in
# `volumes[].secret.secretName` and *reads* it. The parked walker
# (the previous `lib/eval/manifest-projections.nix`) matched `secretName`
# anywhere in the tree and so counted cert-manager's own output as a
# consumption — which is why this is kind-aware rather than a blanket scan.
#
# A reference with no namespace of its own resolves to the resource's, because
# every one of these forms is namespace-local: Kubernetes has no cross-namespace
# Secret reference, so a `namespace` field beside one of these names is either
# the resource's own or a mistake.
{ lib }:

let
  # secretAddress :: Namespace -> Name -> "<ns>/<name>"
  key = namespace: name: "${namespace}/${name}";

  # A resource with no namespace of its own is skipped on both sides.
  #
  # It is either cluster-scoped, in which case the namespace a Secret
  # reference resolves against is not a property of the resource at all — a
  # cert-manager `ClusterIssuer` reads its CA from the controller's resource
  # namespace, which only that floe knows — or it is relying on an apply-time
  # default, and guessing `default` would invent a reference to a Secret in a
  # namespace nobody named. Both would be false positives in a check whose
  # whole value is that a report means something. A floe in that position says
  # so with `needsSecrets`.
  nsOf = res: res.metadata.namespace or null;

  # Producers. Deliberately a closed list rather than a walk: creating a Secret
  # is something a specific kind does, and guessing would put false providers
  # into the graph and silence the very check this exists to feed.
  creators = {
    "Secret" = res: [ (res.metadata.name or null) ];

    # cert-manager writes the issued keypair here.
    "Certificate" = res: [ (res.spec.secretName or null) ];

    # external-secrets materialises into `target.name`, defaulting to the
    # ExternalSecret's own name when it says nothing.
    "ExternalSecret" = res: [ (res.spec.target.name or res.metadata.name or null) ];
  };

  # Consumers, as paths through an arbitrary resource body. Each entry takes a
  # node and returns the names it references, if any.
  #
  # `.secretName` appears here only under a `secret` node (a volume), never
  # bare — bare is the producer form above.
  readersAt = node: [
    (node.secretKeyRef.name or null)
    (node.secretRef.name or null)
    (node.secret.secretName or null)

    # trust-manager's `Bundle.spec.sources[].secret`.
    (node.secret.name or null)
  ];

  # List-valued reference forms, which the generic walk reaches as attrsets but
  # whose shape differs enough to name explicitly.
  readersIn =
    node:
    map (r: r.name or null) (node.imagePullSecrets or [ ])

    # A Gateway listener's `certificateRefs`. `kind` is optional and defaults
    # to Secret, so an entry that names a kind and means something else is
    # skipped rather than reported as a missing Secret.
    ++ map (r: r.name or null) (
      lib.filter (r: (r.kind or "Secret") == "Secret") (node.certificateRefs or [ ])
    );

  walk =
    v:
    if builtins.isAttrs v then
      readersAt v ++ readersIn v ++ lib.concatMap walk (lib.attrValues v)
    else if builtins.isList v then
      lib.concatMap walk v
    else
      [ ];

  # Sorted, so a bundle's token list depends on what it references and not on
  # where in the resource body the reference happened to be found.
  present = names: lib.naturalSort (lib.unique (lib.filter (n: n != null && n != "") names));
in
{
  inherit key;

  # secretsCreatedBy :: resource -> [ "<ns>/<name>" ]
  secretsCreatedBy =
    res:
    let
      kind = res.kind or "";
      names = if creators ? ${kind} then creators.${kind} res else [ ];
    in
    if nsOf res == null then [ ] else map (key (nsOf res)) (present names);

  # secretsUsedBy :: resource -> [ "<ns>/<name>" ]
  secretsUsedBy =
    res: if nsOf res == null then [ ] else lib.unique (map (key (nsOf res)) (present (walk res)));

  secretAddress = key;
}
