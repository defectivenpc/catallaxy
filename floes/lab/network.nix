# The docker network every container in this lab shares.
#
# A fact the lab holds — which network a container joins is a statement about
# what else is on the host, and no floe can derive it — and the two steps that
# make it and unmake it.
#
# Always placed, even by a lab that creates no network. The zone's records
# answer at the gateway address whether or not anything is listening there,
# and `floes/lab/zone.nix` exists precisely so a lab can declare what its
# routes hang off without running a thing. Conditional placement would make
# the zone conditional on the network, which is the wrong way round.
#
# `managed` is what varies instead: whether this lab brings the network into
# existence, or joins one that is already there. A lab of nothing but cloud
# clusters and no host services is on no docker network at all, and a
# `docker network create` in its plan would be a step that means nothing.
{
  lib,
  floe,
  sigs,
  kinds,
  catallaxy,
  ...
}:

let
  inherit (catallaxy) planTokens;
in
floe.mkFloe {
  name = "lab-network";
  summary = "The docker network a lab's containers share, and the steps that make and unmake it.";

  inputs = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "Docker network name, which is the lab's. Required.";
    };

    subnet = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalExpression "the lab's slot in `lib/allocation.nix`";
      description = ''
        The network's range, in CIDR form.

        `cata lab up` parses it before it runs anything, to refuse a lab whose
        subnet overlaps one already on the host.

        Null takes the lab's allocated slot, which is what every lab in this
        tree uses. Subnets are scarce and shared, so the plan is written down
        once and derived from the name rather than chosen per lab.
      '';
    };

    managed = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether this lab creates the network and removes it again.

        False for a lab with nothing on it — every cluster in a cloud and no
        host services — where a `docker network create` would sit in the plan
        looking like a step that means something. The address facts above stay
        true either way, which is why this is an input and not a reason to
        leave the floe out.
      '';
    };
  };

  provides.network = sigs.LAB_NETWORK;
  provides.step = sigs.LAB_STEPS;

  body =
    { inputs, ... }:
    let
      subnet =
        if inputs.subnet != null then inputs.subnet else (catallaxy.allocationFor inputs.name).subnet;

      gateway = (import ../../lib/util/network.nix { inherit lib; }).cidrFirstIP subnet;
    in
    {
      provides.network = {
        inherit (inputs) name;
        inherit subnet gateway;
      };

      provides.step.steps = lib.optionalAttrs inputs.managed {
        docker-network-create = {
          kind = "docker-network-create";
          description = "Create docker network '${inputs.name}'";
          provides = [ planTokens.lab.network ];
          params = {
            inherit (inputs) name;
            inherit subnet gateway;
          };
        };

        remove-network = {
          kind = "remove-network";
          description = "Remove docker network '${inputs.name}'";
          provides = [ planTokens.lab.networkRemoved ];

          afterClusters = "destroyed";
        };
      };
    };
}
