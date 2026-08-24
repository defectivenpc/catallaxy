# The floe set is a parameter, and these are what say so.
#
# `mkLab` defaults it to the set this repo ships, so every other lab in the
# tree exercises exactly one value of it. A parameter with one caller is
# indistinguishable from a constant, and the whole point of separating the
# distro from the platform is that someone can pass a different one.
{
  lib,
  pkgs,
  mkLab,
}:

let
  # Deliberately tiny, and deliberately not a subset anyone would ship: two
  # floes with no gateway, no delivery and no secret store between them. If
  # the platform can still evaluate this, the coupling that remains is
  # coupling it declares rather than coupling it assumes.
  reducedSet = {
    cluster = {
      inherit (import ../../floes/cluster/set.nix) cert-manager reloader;
    };
    lab = { };
  };

  labWith =
    floes:
    mkLab {
      inherit floes;
      modules = [
        {
          lab.name = "floe-set-fixture";
          lab.environment = "development";
          lab.dns.enable = false;
          lab.registry.enable = false;
          lab.proxy.enable = false;
          lab.clusters.app = {
            cluster.name = "app";
            cluster.provisioner = "k3d";
            provisioner.k3d.network = "floe-set-fixture";
            floes.cert-manager.enable = true;
          };
        }
      ];
    };

  reduced = labWith reducedSet;

  present = lib.attrNames reduced.config.lab.clusters.app.floes;
  want = [
    "cert-manager"
    "reloader"
  ];

  # Setting an option of a floe the set left out must be an error, not a
  # silently ignored line. That is the difference between "the set chose the
  # floes" and "the set chose which floes to evaluate eagerly".
  #
  # Run twice, against the reduced set and the default one, because a single
  # failing eval proves nothing: the fixture lab could be wrong for a reason
  # that has nothing to do with the omitted floe. The pair is the evidence — same lab,
  # same line, and the only difference is which set was passed.
  enablingExternalSecretsUnder =
    floes:
    builtins.tryEval (
      builtins.deepSeq
        (mkLab {
          inherit floes;
          modules = [
            {
              lab.name = "floe-set-omitted";
              lab.environment = "development";
              lab.dns.enable = false;
              lab.registry.enable = false;
              lab.proxy.enable = false;
              lab.clusters.app = {
                cluster.name = "app";
                cluster.provisioner = "k3d";
                provisioner.k3d.network = "floe-set-omitted";
                floes.external-secrets.enable = true;
              };
            }
          ];
        }).config.lab.clusters.app.floes.external-secrets.enable
        "evaluated"
    );

  omitted = enablingExternalSecretsUnder reducedSet;
  control = enablingExternalSecretsUnder {
    cluster = import ../../floes/cluster/set.nix;
    lab = import ../../floes/lab/set.nix;
  };
in
{
  a-lab-gets-the-floe-set-it-asked-for = pkgs.runCommand "a-lab-gets-the-floe-set-it-asked-for" { } ''
    ${lib.optionalString (present != want) ''
      echo "a lab built with a two-floe set has floes: ${lib.concatStringsSep ", " present}" >&2
      echo "expected exactly: ${lib.concatStringsSep ", " want}" >&2
      echo "" >&2
      echo "The floe set reached the module tree partially or not at all." >&2
      echo "mkLab's 'floes' argument is threaded to the cluster submodule" >&2
      echo "through specialArgs.clusterFloes; check lib/labs.nix and" >&2
      echo "modules/lab/types.nix." >&2
      exit 1
    ''}
    touch $out
  '';

  a-floe-outside-the-set-is-not-an-option =
    pkgs.runCommand "a-floe-outside-the-set-is-not-an-option" { }
      ''
        ${lib.optionalString omitted.success ''
          echo "a lab set floes.external-secrets.enable under a set containing only" >&2
          echo "cert-manager and reloader, and evaluated without complaint." >&2
          echo "" >&2
          echo "Every floe option tree is still being defined regardless of" >&2
          echo "the set, so declining a floe declines nothing. The imports in" >&2
          echo "modules/lab/types.nix should come only from 'clusterFloes'." >&2
          exit 1
        ''}
        ${lib.optionalString (!control.success) ''
          echo "the same lab failed to evaluate under the full floe set too," >&2
          echo "so the refusal above is not about external-secrets being omitted and" >&2
          echo "this check is proving nothing." >&2
          echo "" >&2
          echo "Fix the fixture lab in nix/checks/floe-sets.nix first." >&2
          exit 1
        ''}
        touch $out
      '';

  # And the reduced lab renders, rather than merely evaluating its options.
  # Rendering is where the platform's assumptions about which floes exist
  # actually bite.
  a-reduced-floe-set-still-renders = reduced.config.lab.out.package;
}
