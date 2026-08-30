# The generated `<lab>-ops` tool, exercised rather than inspected.
#
# `lib/render/ops.nix` emits shell: flag parsing, enum validation, positional
# counting and dispatch. A `lib.runTests` suite over it could only assert on
# the text it produces, which proves nothing about whether that text parses,
# let alone whether `--cluster bogus` is refused. So the fixture is built and
# run, and every case is a real invocation.
#
# The command under test echoes its environment and arguments, so each case
# can assert on exactly what reached it — which is the contract the schema
# makes: options arrive as `OPT_<NAME>`, positionals arrive on `$@`.
{ lib, pkgs }:

let
  opsRender = import ../../lib/render/ops.nix { inherit lib pkgs; };

  echoer = pkgs.writeShellScript "echoer" ''
    echo "cluster=''${OPT_CLUSTER:-} wait=''${OPT_WAIT:-} ttl=''${OPT_TTL:-}"
    echo "args=$*"
  '';

  # Every field the schema declares, because the renderer reads all of them
  # and a fixture that omits one tests the default rather than the field.
  option =
    {
      type ? "str",
      values ? [ ],
      required ? false,
      default ? null,
      description ? "",
    }:
    {
      inherit
        type
        values
        required
        default
        description
        ;
    };

  arg =
    {
      name,
      required ? true,
      variadic ? false,
      description ? "",
    }:
    {
      inherit
        name
        required
        variadic
        description
        ;
    };

  base = {
    description = "";
    command = [ ];
    package = null;
    options = { };
    args = [ ];
  };

  tool = opsRender.mkOpsTool {
    labName = "fixture";
    ops = {
      backup = {
        create = base // {
          description = "Create a backup";
          package = "${echoer}";
          options = {
            cluster = option {
              type = "enum";
              values = [
                "core"
                "obs"
              ];
              required = true;
            };
            wait = option { type = "bool"; };
            ttl = option {
              type = "str";
              default = "720h";
            };
          };
          args = [
            (arg { name = "name"; })
            (arg {
              name = "extra";
              required = false;
              variadic = true;
            })
          ];
        };

        list = base // {
          description = "List backups";
          command = [
            "${pkgs.coreutils}/bin/echo"
            "listing"
          ];
        };
      };

      # A second category holding a command of the same name, which is the
      # case the `<category>/<name>` dispatch exists for.
      restore = {
        list = base // {
          description = "List restores";
          command = [
            "${pkgs.coreutils}/bin/echo"
            "restores"
          ];
        };
      };
    };
  };
in
{
  ops-tool = pkgs.runCommand "ops-tool" { nativeBuildInputs = [ tool ]; } ''
    fail() { echo "FAIL: $1" >&2; echo "  got: $2" >&2; exit 1; }

    # A run that is expected to fail must not take the whole check down, and
    # `set -e` is on in a runCommand, so every negative case goes through this.
    status() { set +e; "$@" >/dev/null 2>&1; echo "$?"; set -e; }

    # ---- dispatch --------------------------------------------------------

    got=$(fixture-ops backup list)
    [ "$got" = "listing" ] || fail "backup list" "$got"

    # The same command name in another category. A case over the name alone
    # would have run whichever branch was written first.
    got=$(fixture-ops restore list)
    [ "$got" = "restores" ] || fail "restore list dispatches separately" "$got"

    got=$(status fixture-ops backup nonesuch)
    [ "$got" = 2 ] || fail "unknown command exits 2" "$got"

    # No arguments is a request for the listing, not a failure.
    got=$(status fixture-ops)
    [ "$got" = 0 ] || fail "bare invocation exits 0" "$got"

    # Options list alphabetically, not in declaration order: `attrNames`
    # sorts, and a signature that claimed otherwise would drift the first time
    # someone added an option.
    fixture-ops 2>&1 \
      | grep -q -- 'create \[--cluster <cluster>\] \[--ttl <ttl>\] \[--wait\] <name> \[extra\]\.\.\.' \
      || fail "listing shows the signature" "$(fixture-ops 2>&1)"

    # ---- options ---------------------------------------------------------

    # Options reach the command as `OPT_<NAME>`, and one the user did not pass
    # is still set — so a command reading it under `set -u` sees the default
    # rather than dying.
    got=$(fixture-ops backup create --cluster core mybackup | head -1)
    [ "$got" = "cluster=core wait= ttl=720h" ] || fail "options arrive as OPT_*, with defaults" "$got"

    got=$(fixture-ops backup create --cluster core mybackup | tail -1)
    [ "$got" = "args=mybackup" ] || fail "positionals arrive on \$@, without the flags" "$got"

    got=$(fixture-ops backup create --cluster obs --wait --ttl 1h mybackup | head -1)
    [ "$got" = "cluster=obs wait=true ttl=1h" ] || fail "bool and str options parse" "$got"

    # ---- validation ------------------------------------------------------

    got=$(status fixture-ops backup create mybackup)
    [ "$got" = 2 ] || fail "a required option is required" "$got"

    got=$(status fixture-ops backup create --cluster bogus mybackup)
    [ "$got" = 2 ] || fail "an enum refuses a value outside its set" "$got"

    # Captured first, not piped: the command exits 2 and `pipefail` would
    # report that rather than grep's match, so the assertion would fail on a
    # message that is in fact correct.
    set +e; msg=$(fixture-ops backup create --cluster bogus mybackup 2>&1); set -e
    echo "$msg" | grep -q 'must be one of core, obs' || fail "the enum error names the set" "$msg"

    got=$(status fixture-ops backup create --cluster)
    [ "$got" = 2 ] || fail "a value option with no value is refused" "$got"

    got=$(status fixture-ops backup create --nope core mybackup)
    [ "$got" = 2 ] || fail "an unknown flag is refused" "$got"

    # ---- positionals -----------------------------------------------------

    got=$(status fixture-ops backup create --cluster core)
    [ "$got" = 2 ] || fail "a required positional is required" "$got"

    # The variadic tail is not counted toward the minimum and reaches the
    # command in order, after the flags are consumed.
    got=$(fixture-ops backup create --cluster core mybackup a b | tail -1)
    [ "$got" = "args=mybackup a b" ] || fail "variadic args pass through" "$got"

    # `--` ends option parsing, so a positional that looks like a flag can
    # still be passed.
    got=$(fixture-ops backup create --cluster core -- --not-a-flag | tail -1)
    [ "$got" = "args=--not-a-flag" ] || fail "-- ends option parsing" "$got"

    touch $out
  '';
}
