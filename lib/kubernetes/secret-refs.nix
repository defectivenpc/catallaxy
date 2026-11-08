{ lib }:

let
  key = namespace: name: "${namespace}/${name}";

  nsOf = res: res.metadata.namespace or null;

  creators = {
    "Secret" = res: [ (res.metadata.name or null) ];

    "Certificate" = res: [ (res.spec.secretName or null) ];

    "ExternalSecret" = res: [ (res.spec.target.name or res.metadata.name or null) ];
  };

  readersAt = node: [
    (node.secretKeyRef.name or null)
    (node.secretRef.name or null)
    (node.secret.secretName or null)

    (node.secret.name or null)
  ];

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

  present = names: lib.naturalSort (lib.unique (lib.filter (n: n != null && n != "") names));
in
{
  inherit key;

  secretsCreatedBy =
    res:
    let
      kind = res.kind or "";
      names = if creators ? ${kind} then creators.${kind} res else [ ];
    in
    if nsOf res == null then [ ] else map (key (nsOf res)) (present names);

  secretsUsedBy =
    res: if nsOf res == null then [ ] else lib.unique (map (key (nsOf res)) (present (walk res)));

  secretAddress = key;
}
