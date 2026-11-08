{ lib }:

let

  readOnlyOperations = [
    "assert"
    "error"
  ];
in
rec {

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
