{ lib }:

let

  readOnlyOperations = [
    "assert"
    "error"
  ];
in
rec {

  /*
    A JMESPath key matching a resource whose `type` condition is present and
    is not `status`.

    The parentheses are load-bearing: `|` binds looser than `&&` in JMESPath,
    so writing the two halves without them parses as a pipeline and quietly
    evaluates to nonsense rather than erroring. The null guard is equally
    load-bearing: selection is a wildcard over the kind, so a resource that
    has not reported the condition yet would otherwise match and fire.
  */
  conditionIsNot =
    {
      type,
      status ? "True",
    }:
    let
      value = "(status.conditions[?type == '${type}'] | [0].status)";
    in
    "(${value} != null && ${value} != '${status}')";

  fieldIsNot = { field, value }: "(${field} != null && ${field} != '${value}')";

  /*
    A check lowered to Chainsaw steps.

    `lib/render/chainsaw.nix` lowers the checks a floe contributed. A floe's
    check is plain data from a kind schema rather than a module, so it never
    reaches `config`.
  */
  stepsFor =
    {
      name,
      timeout ? "2m",
      expect ? null,
      reject ? [ ],
      steps ? [ ],
    }:
    if steps != [ ] then
      steps
    else
      [
        {
          inherit name;
          try =
            lib.optional (expect != null) {
              "assert" = {
                inherit timeout;
                resource = expect;
              };
            }
            ++ map (resource: {
              error = {
                inherit timeout resource;
              };
            }) reject;
        }
      ];

  mutatingOperations =
    steps:
    lib.unique (
      lib.concatMap (
        step:
        lib.concatMap (op: lib.filter (o: !(builtins.elem o readOnlyOperations)) (lib.attrNames op)) (
          (step.try or [ ]) ++ (step.catch or [ ]) ++ (step.finally or [ ])
        )
      ) steps
    );
}
