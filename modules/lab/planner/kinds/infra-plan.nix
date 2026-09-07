{ lib }:

{
  directions = [ "deploy" ];
  idempotency = "idempotent";
  dialsLabEndpoints = false;
  # A plan is read-only and it is not inert: it authenticates and calls the
  # provider's API to read current state. RFC 0003 §8 — "it must not run under
  # a flag that an operator reads as 'nothing will happen'" — and §12.8 makes
  # "a dry run reaches no cloud account" an acceptance criterion.
  #
  # `cli/src/plan/steps/infra.rs` gates the same step on `--infra` as well.
  # This flag covers `--dry-run`; that gate covers a run without `--infra`.
  dryRunSafe = false;
  params.options = {
    stack = lib.mkOption {
      type = lib.types.str;
      description = "Stack this step acts on, which is one unit of state and one apply.";
    };
    workingDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Directory the tool runs in. Null lets the CLI derive it, which is
        what a lab wants: it is host state, not something a lab declares.
      '';
    };
  };
}
