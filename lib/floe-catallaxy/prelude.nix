# The type prelude this distribution speaks: core's, plus the types its domain
# has.
#
# Core carries what any domain would recognise — strings, ports, URLs, DNS
# names, and the two constructors that say when and where a value is usable.
# `k8sName` lived there and was the one thing making core's "contains no
# Kubernetes" false.
#
# Its own file rather than a few lines in `default.nix` because two callers
# need it and only one of them can build the whole distribution: the pure
# `lib/tests` suites take `lib` alone, and `default.nix` needs `pkgs` for the
# renderer.
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
