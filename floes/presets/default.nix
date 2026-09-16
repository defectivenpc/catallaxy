# Presets: floes that include floes.
#
# Kept apart from `floes/` because a preset is built *from* the floe set, so it
# is applied after it. A lab reaches them as `presets.<name>`.
{
  standard-cluster = ./standard-cluster.nix;
}
