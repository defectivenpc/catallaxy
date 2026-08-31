# The HCL renderer.
#
# It exists because OpenBao's config is HCL and Nix is not, and because the
# renderer this replaced put every value through `toString` inside quotes: an
# int became a quoted string, `true` became `"1"`, `false` became `""`, and a
# nested attrset stringified to garbage. A `seal` or a `storage "raft"` block
# with a port or a flag in it came out wrong, and the server refused to start
# with an error about the value's type rather than about where it came from.
{ lib }:

let
  hcl = import ../util/hcl.nix { inherit lib; };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
in
lib.runTests {

  # The bug this file was written for. Each of these is a distinct HCL type
  # and `toString` collapses three of them into a quoted string.
  testEachScalarKeepsItsType = {
    expr = hcl.body "" {
      s = "text";
      i = 8200;
      yes = true;
      no = false;
    };
    expected = ''
      i = 8200
      no = false
      s = "text"
      yes = true
    '';
  };

  # `true` became `"1"` and `false` became `""`, so a flag meant to be off
  # read as an empty string — which HCL accepts and the server reads as unset
  # rather than as false.
  testFalseIsNotTheEmptyString = {
    expr = hcl.body "" { tls_disable = false; };
    expected = "tls_disable = false\n";
  };

  testAQuoteInAStringIsEscaped = {
    expr = hcl.body "" { path = ''a"b''; };
    expected = ''path = "a\"b"'' + "\n";
  };

  testABackslashIsEscaped = {
    expr = hcl.body "" { path = ''a\b''; };
    expected = ''path = "a\\b"'' + "\n";
  };

  testAListRendersInline = {
    expr = hcl.body "" {
      addrs = [
        "a"
        "b"
      ];
    };
    expected = ''addrs = ["a", "b"]'' + "\n";
  };

  # A nested attrset is a nested block, not a stringified attrset.
  testANestedAttrsetIsABlock = {
    expr = hcl.body "" { listener.tcp.address = "[::]:8200"; };
    expected = ''
      listener {
        tcp {
          address = "[::]:8200"
        }
      }
    '';
  };

  # `seal "awskms" { … }` and `storage "raft" { … }`: the label is what
  # distinguishes two blocks of the same kind.
  testALabelledBlock = {
    expr = hcl.block "storage" "file" { path = "/openbao/data"; };
    expected = ''
      storage "file" {
        path = "/openbao/data"
      }
    '';
  };

  # Refused rather than rendered as something the server would misread. A
  # null is the case that matters: it means "not set", and `null = ""` in a
  # config file is a value.
  testAValueWithNoHclFormIsRefused = {
    expr = throws (hcl.body "" { nothing = null; });
    expected = true;
  };
}
