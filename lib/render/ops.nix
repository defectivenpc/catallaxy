# The ops channel -> one `<lab>-ops` executable.
#
# `cata lab ops -- <args>` runs `cliConfig.opsToolPath` with the arguments
# after `--` passed through verbatim, so the dispatch lives here rather than
# in the CLI. The invocation is `<lab>-ops <category> <name> [args...]`, which
# is the shape `lib/floe-catallaxy/elaborate.nix` keys the channel for.
#
# Deliberately small. `component.nix`'s `opsCommandSchema` is
# `{ description, command = listOf str }` and nothing more — no declared
# options, no typed arguments, no per-cluster kubecontext. Those exist in the
# parked `old-floes/lib/render/ops-cli.nix` (317 lines) and come back with the
# schema that needs them, not before.
{ lib, pkgs }:

{
  # mkOpsTool :: { labName; ops } -> package or null
  #
  # `ops` is `cluster.out.ops`: category -> name -> { description, command }.
  # Null when there is nothing to dispatch, so the lab can omit
  # `opsToolPath` rather than shipping a tool that only ever prints that it
  # has no commands.
  mkOpsTool =
    { labName, ops }:
    let
      nonEmpty = lib.filterAttrs (_: cmds: cmds != { }) ops;

      # `<category>/<name>` matched as one word: two categories may each hold
      # a command of the same name, and a case over the name alone would run
      # whichever branch was written first.
      branch = category: name: cmd: ''
        ${category}/${name})
          shift 2
          exec ${lib.escapeShellArgs cmd.command} "$@"
          ;;
      '';

      branches = lib.concatStrings (
        lib.mapAttrsToList (
          category: cmds: lib.concatStrings (lib.mapAttrsToList (branch category) cmds)
        ) nonEmpty
      );

      listing = lib.concatStrings (
        lib.mapAttrsToList (
          category: cmds:
          ''
            echo "  ${category}"
          ''
          + lib.concatStrings (
            lib.mapAttrsToList (name: cmd: ''
              printf '    %-40s %s\n' ${lib.escapeShellArg name} ${lib.escapeShellArg cmd.description}
            '') cmds
          )
        ) nonEmpty
      );
    in
    if nonEmpty == { } then
      null
    else
      pkgs.writeShellApplication {
        name = "${labName}-ops";
        text = ''
          usage() {
            echo "usage: ${labName}-ops <category> <command> [args...]"
            echo
            echo "commands:"
            ${listing}
          }

          if [ "$#" -lt 2 ]; then
            usage
            # No command named is a request for the listing, not a failure.
            # `cata lab ops` with no arguments is how you find out what there
            # is, and a nonzero exit there reads as something being wrong.
            [ "$#" -eq 0 ] && exit 0
            exit 2
          fi

          case "$1/$2" in
            ${branches}
            *)
              echo "${labName}-ops: no command '$1 $2'" >&2
              echo >&2
              usage >&2
              exit 2
              ;;
          esac
        '';
      };
}
