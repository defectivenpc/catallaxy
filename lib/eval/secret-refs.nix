# Which Secrets a resource creates, and which it reads.
{ lib }:

let
  # secretAddress :: Namespace -> Name -> "<ns>/<name>"
  key = namespace: name: "${namespace}/${name}";

  nsOf = res: res.metadata.namespace or null;

  creators = {
    "Secret" = res: [ (res.metadata.name or null) ];

    # cert-manager writes the issued keypair here.
    "Certificate" = res: [ (res.spec.secretName or null) ];

    # external-secrets materialises into `target.name`, defaulting to the
    # ExternalSecret's own name when it says nothing.
    "ExternalSecret" = res: [ (res.spec.target.name or res.metadata.name or null) ];
  };

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
