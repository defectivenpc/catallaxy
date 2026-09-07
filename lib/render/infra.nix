# Stacks, and the `main.tf.json` each one renders to.
{ lib }:

let
  localRef =
    type: name: attr:
    "\${${type}.${name}.${attr}}";
  remoteRef = stack: output: "\${data.terraform_remote_state.${stack}.outputs.${output}}";

  outputName = resource: output: "${resource}_${output}";

  isToken = v: builtins.isAttrs v && (v.__deferred or false) == true;

  interpolate =
    resolve: v:
    if isToken v then
      resolve v
    else if builtins.isAttrs v then
      lib.mapAttrs (_: interpolate resolve) v
    else if builtins.isList v then
      map (interpolate resolve) v
    else
      v;
in
rec {
  inherit outputName;

  # stackNameFor :: scope -> unit -> phase -> string
  #
  # `scope` is the cluster the floe was instantiated in, or `lab` for one the
  # lab holds. Two labs are two instantiations by `lab.name` already, since
  # every stack's state lives under the lab's own directory.
  stackNameFor =
    scope: unit: phase:
    "${scope}-${unit}-${phase}";

  # Every stack in a lab, with the resources and publications that belong to
  # it, from the per-unit output collections the linker produced.
  #
  # collectStacks :: { scope; resources; publications; } -> { <stack> = { … } }
  collectStacks =
    {
      scope,
      resources ? { },
      publications ? { },
    }:
    let
      placed = lib.concatLists (
        lib.mapAttrsToList (
          unit: rs:
          lib.mapAttrsToList (rname: r: {
            inherit unit rname r;
            stack = stackNameFor scope unit r.phase;
          }) rs
        ) resources
      );

      stackNames = lib.unique (map (p: p.stack) placed);

      stackOfResource =
        unit: rname:
        let
          hit = lib.filter (p: p.unit == unit && p.rname == rname) placed;
        in
        if hit == [ ] then null else (lib.head hit).stack;
    in
    lib.listToAttrs (
      map (
        name:
        let
          mine = lib.filter (p: p.stack == name) placed;
        in
        lib.nameValuePair name {
          resources = lib.listToAttrs (map (p: lib.nameValuePair p.rname p.r) mine);

          units = lib.unique (map (p: p.unit) mine);

          publications = lib.concatLists (
            lib.mapAttrsToList (
              unit: ps:
              lib.mapAttrsToList (_: p: p // { inherit unit; }) (
                lib.filterAttrs (_: p: stackOfResource unit p.resource == name) ps
              )
            ) publications
          );
        }
      ) stackNames
    );

  # The document the tool reads. Pure data; `builtins.toJSON` of this is the
  # file, so it is diffable as a fixture without building anything.
  #
  # renderStack :: { name; stack; stacks; providers; stateDir } -> attrs
  renderStack =
    {
      name,
      stack,
      stacks,
      providers,
      stateDir,
    }:
    let
      resolveToken =
        tok:
        let
          path = tok.path or [ ];
          rname = lib.elemAt path 0;
          attr = lib.elemAt path 1;

          here = stack.resources.${rname} or null;

          owner = lib.findFirst (s: (stacks.${s}.resources or { }) ? ${rname}) null (lib.attrNames stacks);
        in
        if lib.length path != 2 then
          throw (
            "infra: a resource reference names ${toString (lib.length path)} "
            + "part(s) (${lib.concatStringsSep "." path}); it takes two, a resource and one of "
            + "its declared outputs"
          )
        else if here != null then
          localRef here.type rname attr
        else if owner == null then
          throw ("infra: stack '${name}' refers to resource '${rname}', which no floe in this lab declares")
        else if !(lib.elem attr stacks.${owner}.resources.${rname}.outputs) then
          throw (
            "infra: stack '${name}' reads '${rname}.${attr}', and '${rname}' declares "
            + "outputs [${lib.concatStringsSep ", " stacks.${owner}.resources.${rname}.outputs}]. "
            + "Outputs are declared, not inferred, so a name that is not in that list is a typo "
            + "rather than a value that happens to be missing."
          )
        else
          remoteRef owner (outputName rname attr);

      readsFrom = lib.unique (
        lib.concatLists (
          lib.mapAttrsToList (
            _: r:
            lib.concatMap (
              tok:
              let
                rname = lib.elemAt (tok.path or [ ]) 0;
                owner = lib.findFirst (s: (stacks.${s}.resources or { }) ? ${rname}) null (lib.attrNames stacks);
              in
              lib.optional (owner != null && owner != name) owner
            ) (tokensIn r.inputs)
          ) stack.resources
        )
      );

      usedProviders = lib.unique (lib.mapAttrsToList (_: r: r.provider) stack.resources);

      # Grouped `type -> name -> inputs`, which is the tool's own shape.
      byType = lib.mapAttrs (_: rs: lib.listToAttrs rs) (
        lib.groupBy (e: e.type) (
          lib.mapAttrsToList (rname: r: {
            inherit (r) type;
            name = rname;
            value = interpolate resolveToken r.inputs;
          }) stack.resources
        )
      );
    in
    {
      terraform = {
        required_providers = lib.listToAttrs (
          map (
            p:
            lib.nameValuePair p (
              providers.${p}
                or (throw "infra: stack '${name}' uses provider '${p}', which the lab pins no version for")
            )
          ) usedProviders
        );
      };
    }
    // lib.optionalAttrs (readsFrom != [ ]) {
      data.terraform_remote_state = lib.listToAttrs (
        map (
          s:
          lib.nameValuePair s {
            backend = "local";
            # Built from where the producer's state actually is, rather than
            # restated. Two descriptions of one path will disagree.
            config.path = "${stateDir}/${s}/terraform.tfstate";
          }
        ) readsFrom
      );
    }
    // {
      resource = byType;

      output = lib.listToAttrs (
        lib.concatLists (
          lib.mapAttrsToList (
            rname: r:
            map (
              o:
              lib.nameValuePair (outputName rname o) {
                value = localRef r.type rname o;
                sensitive = true;
              }
            ) r.outputs
          ) stack.resources
        )
      );
    };

  # Every deferred token in a value, wherever it sits.
  tokensIn =
    v:
    if isToken v then
      [ v ]
    else if builtins.isAttrs v then
      lib.concatMap tokensIn (lib.attrValues v)
    else if builtins.isList v then
      lib.concatMap tokensIn v
    else
      [ ];

  dependenciesOf =
    stacks: name:
    let
      stack = stacks.${name};
    in
    lib.unique (
      lib.concatLists (
        lib.mapAttrsToList (
          _: r:
          lib.concatMap (
            tok:
            let
              rname = lib.elemAt (tok.path or [ ]) 0;
              owner = lib.findFirst (s: (stacks.${s}.resources or { }) ? ${rname}) null (lib.attrNames stacks);
            in
            lib.optional (owner != null && owner != name) owner
          ) (tokensIn r.inputs)
        ) stack.resources
      )
    );
}
