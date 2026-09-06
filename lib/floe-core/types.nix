# Floe type universe.
#
# These are *data schemas*, not NixOS option types. They describe values that
# cross floe boundaries (signature fields, output kind schemas). Per the
# type-language rule: things that cross the serialization boundary are floe
# data schemas; floe inputs use native NixOS option types instead.
{ lib }:

let
  inherit (builtins)
    isString
    isInt
    isBool
    isAttrs
    isList
    typeOf
    match
    elem
    hasAttr
    ;

  short =
    v:
    if isString v then
      "\"${v}\""
    else if isAttrs v then
      "an attrset"
    else if isList v then
      "a list"
    else
      lib.generators.toPretty { multiline = false; } v;
in
rec {
  any = {
    tag = "any";
    name = "any";
    check = _: true;
  };
  str = {
    tag = "str";
    name = "string";
    check = isString;
  };
  int = {
    tag = "int";
    name = "int";
    check = isInt;
  };
  bool = {
    tag = "bool";
    name = "bool";
    check = isBool;
  };

  port = {
    tag = "port";
    name = "port (1-65535)";
    check = v: isInt v && v >= 1 && v <= 65535;
  };

  url = {
    tag = "url";
    name = "url (http/https)";
    check = v: isString v && match "https?://.+" v != null;
  };

  dnsName = {
    tag = "dnsName";
    name = "DNS name";
    check = v: isString v && match "[a-z0-9]([-a-z0-9.]*[a-z0-9])?" v != null;
  };

  # `k8sName` used to be here, and it was the one thing in this file that made
  # the header's claim false. A distribution extends the prelude with the
  # types its domain has — `lib/floe-catallaxy/default.nix` adds that one —
  # and core carries only what any domain would recognise.
  #
  # `dnsName` stays: DNS is not Kubernetes.

  enum = values: {
    tag = "enum";
    inherit values;
    name = "one of [${lib.concatMapStringsSep ", " (v: "\"${toString v}\"") values}]";
    check = v: elem v values;
  };

  nullOr = inner: {
    tag = "nullOr";
    inherit inner;
    name = "null or ${inner.name}";
  };
  listOf = inner: {
    tag = "listOf";
    inherit inner;
    name = "list of ${inner.name}";
  };
  attrsOf = inner: {
    tag = "attrsOf";
    inherit inner;
    name = "attrs of ${inner.name}";
  };
  deferred = inner: {
    tag = "deferred";
    inherit inner;
    name = "deferred ${inner.name}";
  };

  # A value that means something only inside the link that produced it.
  #
  # The sibling of `deferred`, on a different axis: `deferred` says *when* a
  # value is usable — not until after apply — and this says *where*. A Service
  # address, a namespace, a CRD installed here, a reference to a Secret in this
  # cluster, an annotation only this cluster's controller watches.
  #
  # Not "looks like an address". `CONFIG_RELOAD`'s annotation keys are ordinary
  # strings and are local, because writing them on a workload somewhere else
  # does nothing at all — the reloader that reads them is not there.
  #
  # Inside its own link this is exactly `inner`; `checkValue` passes straight
  # through. It bites in one place: `link` seals a provide arriving from
  # another link by replacing every local field with a throw, so reading one
  # across a boundary is an error naming the field and where it came from, and
  # not reading it is fine. That is the granularity a per-signature flag cannot
  # reach — every signature here is a mix, and `GIT_REPOSITORY` carried the
  # distinction in prose ("only one of them resolves in both places") for want
  # of a type to put it in.
  local = inner: {
    tag = "local";
    inherit inner;
    name = "link-local ${inner.name}";
  };

  isLocal = ty: (ty.tag or "") == "local";

  # A NixOS module type, used as a checker.
  #
  # The rule everywhere else here is that a kind schema holds pure data: the
  # linker's scan walks every output recursively and `nix eval --json` has to
  # serialise it. That rule is about **values**. A schema is only ever an
  # argument to `checkValue` (`link.nix`) and is never itself serialised or
  # walked, so it may hold a function — and `lib.evalModules` returns a plain
  # attrset, so the value stays as pure as the rule requires.
  #
  # What it buys is defaults and per-field types for a surface too irregular
  # for `record`. `steps` is the case: it was `attrsOf any`, normalised at the
  # lab through the same submodule, which meant a malformed step named the lab
  # rather than the floe that wrote it.
  moduleType = inner: {
    tag = "moduleType";
    inherit inner;
    name = "module type ${inner.description or "<anonymous>"}";
  };

  # A record: all declared fields must be present and well-typed.
  # Checking a record also *restricts* to the declared fields (opaque sealing).
  record = fields: {
    tag = "record";
    inherit fields;
    name = "record { ${lib.concatStringsSep ", " (lib.attrNames fields)} }";
  };

  # A value that is exactly one of several shapes, saying which by the name it
  # is under: `{ k3d = { … }; }`.
  #
  # `record` cannot express this. A record with one field per variant makes
  # every variant required, so a shape that is not k3d has to emit a k3d block
  # anyway — which is how `catallaxy.cluster` came to carry one, and why the
  # comment on the provisioner floe saying "the provisioner is not a closed
  # set" was true of the floe and false of the kind it emitted.
  #
  # Nor does an `enum` discriminator beside an untagged record. Then the tag
  # and the block are two facts that can disagree, and the disagreement is
  # exactly the one nothing catches: a value tagged `talos` carrying k3d
  # settings type-checks perfectly and means nothing.
  #
  # Serialises as serde's default externally-tagged representation, so a Rust
  # `enum` reads it with no custom deserialiser and gets exactly-one-variant
  # from the same place this does.
  taggedUnion = variants: {
    tag = "taggedUnion";
    inherit variants;
    name = "tagged union { ${lib.concatStringsSep " | " (lib.attrNames variants)} }";
  };

  isDeferredToken = v: isAttrs v && (v.__deferred or false) == true;

  # checkValue :: [string] -> type -> value -> value
  # Throws with a dotted path on mismatch; returns the (restricted) value.
  checkValue =
    path: ty: v:
    let
      where = if path == [ ] then "<value>" else lib.concatStringsSep "." path;
      fail = msg: throw "floe type error at ${where}: ${msg}";
    in
    if ty.tag == "any" then
      v
    else if ty.tag == "local" then
      # Transparent here. Locality is about which *link* is reading, which a
      # type check has no way to know — so it is enforced where that is known,
      # at the one seam where a value crosses (`link.nix`).
      checkValue path ty.inner v
    else if ty.tag == "deferred" then
      (if isDeferredToken v then v else checkValue path ty.inner v)
    else if isDeferredToken v then
      fail (
        "got a deferred value (from '${toString (v.source or "?")}', resolves "
        + "'${toString (v.phase or "later")}') where concrete ${ty.name} is required"
      )
    else if ty.tag == "nullOr" then
      (if v == null then v else checkValue path ty.inner v)
    else if ty.tag == "listOf" then
      (
        if !isList v then
          fail "expected ${ty.name}, got ${typeOf v}"
        else
          lib.imap0 (i: x: checkValue (path ++ [ (toString i) ]) ty.inner x) v
      )
    else if ty.tag == "attrsOf" then
      (
        if !isAttrs v then
          fail "expected ${ty.name}, got ${typeOf v}"
        else
          lib.mapAttrs (n: x: checkValue (path ++ [ n ]) ty.inner x) v
      )
    else if ty.tag == "moduleType" then
      # `_file` so a type error names the floe's path rather than
      # `<unknown-file>`, and `deepSeq` so it surfaces here — with this
      # `where` in the message — rather than wherever the value is first read.
      (
        let
          evaluated =
            (lib.evalModules {
              modules = [
                { options.value = lib.mkOption { type = ty.inner; }; }
                {
                  value = v;
                  _file = where;
                }
              ];
            }).config.value;
        in
        builtins.deepSeq evaluated evaluated
      )
    else if ty.tag == "record" then
      (
        if !isAttrs v then
          fail "expected ${ty.name}, got ${typeOf v}"
        else
          let
            missing = lib.filter (f: !(hasAttr f v)) (lib.attrNames ty.fields);
          in
          if missing != [ ] then
            fail "missing field(s): ${lib.concatStringsSep ", " missing}"
          else
            lib.mapAttrs (f: fty: checkValue (path ++ [ f ]) fty v.${f}) ty.fields
      )
    else if ty.tag == "taggedUnion" then
      (
        let
          known = lib.attrNames ty.variants;
          expected = "expected exactly one of [${lib.concatStringsSep ", " known}]";
          present = lib.attrNames v;
          unknown = lib.subtractLists known present;
        in
        if !isAttrs v then
          fail "expected ${ty.name}, got ${typeOf v}"
        else if unknown != [ ] then
          # Named before the count, because a misspelt variant is also a
          # wrong count and reporting that first sends the reader looking
          # for a second variant they never wrote.
          fail "no variant named ${lib.concatMapStringsSep ", " (n: "'${n}'") unknown}; ${expected}"
        else if present == [ ] then
          fail "names no variant; ${expected}"
        else if lib.length present > 1 then
          fail (
            "names ${toString (lib.length present)} variants at once "
            + "(${lib.concatStringsSep ", " present}); a tagged union carries one. ${expected}"
          )
        else
          let
            k = lib.head present;
          in
          {
            ${k} = checkValue (path ++ [ k ]) ty.variants.${k} v.${k};
          }
      )
    else if ty ? check then
      (if ty.check v then v else fail "expected ${ty.name}, got ${short v}")
    else
      fail "unknown floe type (tag: ${toString (ty.tag or "missing")})";
}
