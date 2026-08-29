{ lib }:

let
  inherit (lib) mkOption types;
in
{
  generateType = types.submodule (
    { name, ... }:
    {
      options = {
        namespace = mkOption {
          type = types.str;
          description = "Namespace to materialise the Secret in.";
        };

        secret = mkOption {
          type = types.str;
          default = name;
          description = "Name of the Secret. Defaults to the attribute name.";
        };

        key = mkOption {
          type = types.str;
          default = "password";
          description = "Key within the Secret that the value lands under.";
        };

        extraData = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = {
            admin-user = "admin";
          };
          description = ''
            Literal keys to place in the same Secret alongside the generated
            one, written verbatim.

            For a consumer that reads a credential pair out of one Secret and
            will not start without both keys. Grafana is the case this exists
            for: its chart reads `admin-user` and `admin-password` from the
            Secret named by `admin.existingSecret`, and a username is not a
            secret, so there is nothing to generate for it.

            Nothing here is encoded, whatever `encoding` says: that setting
            describes the generated value, and a literal is already the value
            the consumer wants.
          '';
        };

        length = mkOption {
          type = types.int;
          default = 24;
          description = ''
            Characters in the generated value. Under `encoding = "base64"`
            this counts the bytes the consumer decodes, not the characters
            that reach the Secret.
          '';
        };

        digits = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "How many digits. Null lets the generator take a quarter of the length.";
        };

        symbols = mkOption {
          type = types.int;
          default = 0;
          description = ''
            How many symbol characters. Zero, because a consumer that puts the
            value in a URL, a connection string or a config file it does not
            quote breaks on them, and a caller who wants symbols knows it.
          '';
        };

        symbolCharacters = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Which symbols to draw from. Null takes the generator's set.";
        };

        allowRepeat = mkOption {
          type = types.bool;
          default = true;
          description = "Whether a character may appear more than once.";
        };

        noUpper = mkOption {
          type = types.bool;
          default = false;
          description = "Draw from lowercase only.";
        };

        encoding = mkOption {
          type = types.enum [
            "plain"
            "base64"
          ];
          default = "plain";
          description = ''
            How the value reaches the Secret.

            `base64` is for a consumer that decodes the value to get raw key
            bytes rather than reading it as a string, which is what an
            encryption key usually is. It satisfies a consumer that treats the
            value as an opaque string too, so it is the safe choice when you
            are unsure which one you have.
          '';
        };
      };
    }
  );
}
