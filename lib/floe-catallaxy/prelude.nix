# The type prelude this distribution speaks: core's, plus the types its domain
# has.
{ lib }:

let
  core = import ../floe-core { inherit lib; };

  T = core.T // {
    k8sName = {
      tag = "k8sName";
      name = "kubernetes name (DNS-1123 label)";
      check =
        v:
        builtins.isString v
        && builtins.stringLength v <= 63
        && builtins.match "[a-z0-9]([-a-z0-9]*[a-z0-9])?" v != null;
    };
  };
in
core // { inherit T; }
