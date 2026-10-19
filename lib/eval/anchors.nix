{ }:

{
  needs = token: "provides:${token}";

  wants = token: "optional:provides:${token}";
}
