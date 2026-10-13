# The ops channel -> one `<lab>-ops <category> <name> [args...]` executable.
#
# A command runs either `command` (a fixed argv) or `package` (an executable),
# and may declare `options` (`--<name> <value>`, or bare for a bool) and
# positional `args`. Options reach it as `OPT_<NAME>` in the environment.
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

      optNames = cmd: lib.attrNames cmd.options;

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
