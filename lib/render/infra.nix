# Stacks, and the `main.tf.json` each one renders to.
#
# A stack is one state file and one apply, keyed `(instantiation, phase)` —
# RFC 0003 §5. Derived, never named: nobody should have to invent a global
# stack name and hope two floes agree, which is the untyped shared namespace
# RFC 0001 spent its length removing.
#
# Keyed on the *instantiation* rather than the definition because one
# definition is instantiated many times, and keying on the definition would
# put two environments' resources in one state file with colliding addresses —
# so each would plan to destroy the other's.
#
# Not keyed on the reference graph, either. State is stateful: if membership
# were the connected components of the reference graph, adding one reference
# would merge two stacks, and the merged stack has empty state, so it plans to
# create everything while the old states still hold the originals. The tool
# will not migrate between state files on its own.
{ lib }:

let
  # `${type.name.attr}` — the tool's own interpolation, inside one stack.
  #
  # A reference that crosses a stack becomes a remote-state read instead, and
  # the remote-state configuration is built from the producer's own backend
  # rather than restated (RFC 0003 §10): two descriptions of where a state
  # file lives will disagree.
  localRef =
    type: name: attr:
    "\${${type}.${name}.${attr}}";
  remoteRef = stack: output: "\${data.terraform_remote_state.${stack}.outputs.${output}}";

  # A stack's outputs are named `<resource>_<output>`, flat, because that is
  # what `cli/src/domain/lab.rs`'s `InfraPublication.output_name` documents
  # and what `tofu output -json` hands back.
  outputName = resource: output: "${resource}_${output}";

  isToken = v: builtins.isAttrs v && (v.__deferred or false) == true;

  # Walk a resource's inputs and turn every deferred token into the tool's own
  # interpolation syntax.
  #
  # `resolve` is given the token and answers a string, so this function knows
  # nothing about stacks — which is what keeps the local/remote distinction in
  # one place instead of threaded through the walk.
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
      # One entry per (unit, resource), tagged with the stack it lands in.
      # Flattened before grouping because the phase is per *resource*, so one
      # unit's resources can land in two stacks.
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

      # A publication names a resource; the stack follows from that resource's
      # phase. Declaring the phase on the publication as well would be a
      # second copy of one fact, and the two could disagree.
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

          # Which unit contributed it, kept for error messages: a stack name
          # is derived, so a message naming only the stack makes the reader
          # work backwards to the floe that wrote the resource.
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
      # Which resource a token refers to, and whether it is in this stack.
      #
      # The token carries the unit that made it and the path it named, which
      # is `[ resource output ]`.
      resolveToken =
        tok:
        let
          path = tok.path or [ ];
          rname = lib.elemAt path 0;
          attr = lib.elemAt path 1;

          here = stack.resources.${rname} or null;

          # The stack holding it, searched across the lab rather than assumed
          # local: a reference to another floe's resource is ordinary, and the
          # difference between the two is exactly what decides interpolation
          # against remote state.
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

      # Which other stacks this one reads from, so the remote-state data
      # sources can be declared. Derived from the references themselves —
      # nothing is declared, and so nothing can be forgotten (RFC 0003 §10).
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

      # One output per declared attribute, whether or not anything reads it.
      # `tofu output -json` is how the publication step gets a value, and it
      # can only return what the stack declares.
      #
      # All marked sensitive, and not because we know which ones are. This
      # block is a machine interface — it exists so the apply step can read
      # values out and hand them to a secret store — and nothing reads it as
      # a report. Marking them uniformly keeps values off the terminal and
      # out of CI logs, and `-json` still returns them, which is the only
      # reader there is.
      #
      # It is also what the tool requires rather than a preference: a
      # provider marks its own attributes sensitive (`random_password.result`
      # is), and re-exporting one unmarked is refused outright — so the
      # alternative is a per-output flag whose right value is the provider's
      # to know and a lab author's to guess wrong.
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

  # Which stacks each stack must follow, from the references alone.
  #
  # It is A's *plan* that waits on B's apply, not A's apply: rendering A's
  # plan needs B's recorded state. Teardown reverses it — a stack is destroyed
  # after everything that reads from it.
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
