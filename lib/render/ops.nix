# The ops channel -> one `<lab>-ops` executable.
#
# `cata lab ops -- <args>` runs `cliConfig.opsToolPath` with the arguments
# after `--` passed through verbatim, so the dispatch lives here rather than
# in the CLI. The invocation is `<lab>-ops <category> <name> [args...]`, which
# is the shape `lib/floe-catallaxy/elaborate.nix` keys the channel for.
#
# A command says what runs with either `command` (a fixed argv) or `package`
# (a store path to an executable), and may declare `options` — parsed as
# `--<name> <value>`, or `--<name>` for a bool — and `args`, which are
# positional. Options reach the command as `OPT_<NAME>` in the environment,
# which is what lets a `package` script be an ordinary shell script rather
# than something that has to re-parse its own flags.
{ lib, pkgs }:

let
  # `--backup-name` becomes `OPT_BACKUP_NAME`. Uppercased as well as
  # de-hyphenated: a lowercase exported name collides with the ordinary shell
  # environment far too easily, and `OPT_path` beside `PATH` is the kind of
  # thing that works until it does not.
  shellVar = n: "OPT_" + lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] n);
in
{
  # mkOpsTool :: { labName; ops } -> package or null
  #
  # `ops` is `cluster.out.ops`: category -> name -> command.
  # Null when there is nothing to dispatch, so the lab can omit
  # `opsToolPath` rather than shipping a tool that only ever prints that it
  # has no commands.
  mkOpsTool =
    { labName, ops }:
    let
      nonEmpty = lib.filterAttrs (_: cmds: cmds != { }) ops;

      # ---- per-command shell ----------------------------------------------

      optNames = cmd: lib.attrNames cmd.options;

      # Every option gets its variable set before parsing, so a command that
      # reads one the user did not pass sees the default rather than tripping
      # `set -u`. A bool with no default is "", which is falsy in the `[ -n ]`
      # test a script would use.
      initOptions =
        cmd:
        lib.concatMapStrings (
          n:
          let
            opt = cmd.options.${n};
          in
          "    export ${shellVar n}=${lib.escapeShellArg (if opt.default != null then opt.default else "")}\n"
        ) (optNames cmd);

      parseOptions =
        cmd:
        let
          branches = lib.concatMapStrings (
            n:
            let
              opt = cmd.options.${n};
            in
            if opt.type == "bool" then
              "        --${n}) export ${shellVar n}=true; shift ;;\n"
            else
              ''
                --${n})
                  if [ "$#" -lt 2 ]; then echo "${labName}-ops: --${n} needs a value" >&2; exit 2; fi
                  export ${shellVar n}="$2"; shift 2 ;;
              ''
          ) (optNames cmd);
        in
        lib.optionalString (branches != "") ''
              while [ "$#" -gt 0 ]; do
                case "$1" in
          ${branches}      --) shift; break ;;
                  -*) echo "${labName}-ops: unknown flag '$1'" >&2; exit 2 ;;
                  *) break ;;
                esac
              done
        '';

      # Required-ness and enum membership, both before anything runs. An
      # unchecked `--cluster` reaches the underlying tool as an unknown
      # kubecontext, and what that reports is the tool's problem, not ours.
      validateOptions =
        cmd:
        lib.concatMapStrings (
          n:
          let
            opt = cmd.options.${n};
            var = shellVar n;
          in
          lib.optionalString opt.required ''
            if [ -z "''$${var}" ]; then
              echo "${labName}-ops: --${n} is required" >&2
              exit 2
            fi
          ''
          + lib.optionalString (opt.type == "enum" && opt.values != [ ]) ''
            if [ -n "''$${var}" ]; then
              case "''$${var}" in
                ${lib.concatMapStringsSep "|" lib.escapeShellArg opt.values}) ;;
                *) echo "${labName}-ops: --${n} must be one of ${lib.concatStringsSep ", " opt.values}" >&2; exit 2 ;;
              esac
            fi
          ''
        ) (optNames cmd);

      # Positionals are counted, not named: what is left on `$@` is passed
      # through, so a `package` script reads them as `$1`, `$2` in the order
      # declared. A variadic last arg means "and the rest", so it sets no
      # minimum of its own.
      validateArgs =
        cmd:
        let
          required = lib.length (lib.filter (a: a.required && !a.variadic) cmd.args);
          usage = lib.concatMapStringsSep " " (
            a: (if a.required then "<${a.name}>" else "[${a.name}]") + lib.optionalString a.variadic "..."
          ) cmd.args;
        in
        lib.optionalString (required > 0) ''
          if [ "$#" -lt ${toString required} ]; then
            echo "${labName}-ops: expected ${usage}" >&2
            exit 2
          fi
        '';

      runLine =
        cmd:
        if cmd.package != null then
          ''exec ${lib.escapeShellArg cmd.package} "$@"''
        else
          ''exec ${lib.escapeShellArgs cmd.command} "$@"'';

      # `<category>/<name>` matched as one word: two categories may each hold
      # a command of the same name, and a case over the name alone would run
      # whichever branch was written first.
      branch = category: name: cmd: ''
        ${category}/${name})
            shift 2
        ${initOptions cmd}${parseOptions cmd}${validateOptions cmd}${validateArgs cmd}    ${runLine cmd}
            ;;
      '';

      branches = lib.concatStrings (
        lib.mapAttrsToList (
          category: cmds: lib.concatStrings (lib.mapAttrsToList (branch category) cmds)
        ) nonEmpty
      );

      # ---- listing ---------------------------------------------------------

      signature =
        cmd:
        lib.concatStrings (
          map (n: " [--${n}${lib.optionalString (cmd.options.${n}.type != "bool") " <${n}>"}]") (optNames cmd)
          ++ map (
            a: " " + (if a.required then "<${a.name}>" else "[${a.name}]") + lib.optionalString a.variadic "..."
          ) cmd.args
        );

      listing = lib.concatStrings (
        lib.mapAttrsToList (
          category: cmds:
          ''
            echo "  ${category}"
          ''
          + lib.concatStrings (
            lib.mapAttrsToList (name: cmd: ''
              printf '    %-46s %s\n' ${
                lib.escapeShellArg (name + signature cmd)
              } ${lib.escapeShellArg cmd.description}
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
