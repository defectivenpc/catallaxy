{ lib }:

let
  hcl = import ../util/hcl.nix { inherit lib; };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
in
lib.runTests {

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

  testALabelledBlock = {
    expr = hcl.block "storage" "file" { path = "/openbao/data"; };
    expected = ''
      storage "file" {
        path = "/openbao/data"
      }
    '';
  };

  testAValueWithNoHclFormIsRefused = {
    expr = throws (hcl.body "" { nothing = null; });
    expected = true;
  };
}
