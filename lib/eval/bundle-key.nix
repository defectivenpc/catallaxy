# A bundle key is path-shaped; a directory name cannot hold the separator.
{ }:

{
  sanitize = builtins.replaceStrings [ "/" ] [ "__" ];
}
