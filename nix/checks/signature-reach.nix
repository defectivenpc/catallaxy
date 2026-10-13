# Every signature something provides, some hole reads.
#
# `every-floe` exists so that no floe goes unrendered, because a floe no lab
# renders is a floe whose declarations nothing checks. The same argument
# applies one level down: a `provides` no hole anywhere resolves is an
# interface tested at no joint. `providersVerifyWhatTheyPromise` checks a
# promise against the floe that made it, which is the easy half — the hard
# half is whether the shape is one a consumer can actually read, and only a
# consumer finds that out.
#
# It is how `STORAGE_CLASS` went unnoticed. `openebs` promised one, six floes
# rendered a PersistentVolumeClaim, and nothing joined the two: on k3d the
# cluster default absorbed it and on a cluster without one the PVC would have
# sat Pending forever.
#
# Every definition in the tree, which is the catalogue plus every lab's own
# cluster floes — those declare holes too, and `CLUSTER_EDGE` and `LAB_CA` are
# read from nowhere else.
#
# An entry in `unread` is a decision, not a backlog: a capability shipped
# before its consumer, or a promise whose only would-be reader needs a
# different shape. Each carries why. A signature that gains a consumer makes
# its entry stale and fails too, so the list cannot rot into a suppression.
{
  lib,
  pkgs,
  floes,
  labDefs,

  # signature -> why nothing reads it.
  unread ? { },
}:

let
  sigsOf = def: surface: map (s: s.name) (lib.attrValues (def.${surface} or { }));

  clusterFloes = lib.concatMap (lab: map (c: c.clusterFloe.def) (lib.attrValues lab.clusters)) (
    lib.attrValues labDefs
  );

  defs = lib.attrValues floes ++ clusterFloes;

  provided = lib.unique (lib.concatMap (d: sigsOf d "provides") defs);

  consumed = lib.unique (
    lib.concatMap (
      d:
      lib.concatMap (surface: sigsOf d surface) [
        "requires"
        "optional"
        "collects"
      ]
    ) defs
  );

  unreachable = lib.filter (s: !(lib.elem s consumed)) provided;

  undeclared = lib.subtractLists (lib.attrNames unread) unreachable;
  stale = lib.filter (s: lib.elem s consumed) (lib.attrNames unread);

  report = pkgs.writeText "signature-reach" (
    lib.concatStringsSep "\n" (map (s: "unread: ${s}  — ${unread.${s}}") (lib.attrNames unread))
  );
in
{
  signature-reach = pkgs.runCommand "signature-reach" { } ''
    ${lib.optionalString (undeclared != [ ]) ''
      echo "a signature is provided and no hole anywhere reads it:" >&2
      ${lib.concatMapStringsSep "\n" (s: ''echo "  ${s}" >&2'') undeclared}
      cat >&2 <<'EOF'

      A provide no consumer resolves is an interface checked at no joint.
      `providersVerifyWhatTheyPromise` compares a promise against the floe
      that made it; whether the shape is one a peer can read is something
      only a peer finds out.

      Either give it a consumer — a floe that declares the hole — or record
      why nothing reads it, in `unread` at the call site in
      nix/checks/default.nix. An entry there is a decision with a reason
      beside it, which is the point.
      EOF
      exit 1
    ''}

    ${lib.optionalString (stale != [ ]) ''
      echo "these are listed as unread and now have a consumer:" >&2
      ${lib.concatMapStringsSep "\n" (s: ''echo "  ${s}" >&2'') stale}
      echo "" >&2
      echo "Delete them from \`unread\` in nix/checks/default.nix." >&2
      exit 1
    ''}

    cp ${report} $out
  '';
}
