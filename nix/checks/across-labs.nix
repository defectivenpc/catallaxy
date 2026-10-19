# What two labs do to each other, which neither one can know.
#
# Everything about a lab is named after it and cannot clash. Its subnet and its
# host ports are the two things it has to be *given* on purpose, and two labs
# that cannot be up at once is a fact nobody discovers until the second one
# fails to start.
#
# Here rather than in a policy because the subject is the *pair*. A policy sees
# one link, and one lab is correct on its own in every case below — the fault
# only exists in the set of labs this repository builds, which no floe is a
# member of.
{
  lib,
  pkgs,
  labDefs,
}:

let
  net = import ../../lib/util/network.nix { inherit lib; };
  refuse = import ./refuse.nix { inherit lib pkgs; };

  subnetOf = lab: lab.subnet;

  subnetClashes = lib.concatLists (
    lib.mapAttrsToList (
      a: labA:
      lib.concatLists (
        lib.mapAttrsToList (
          b: labB:
          lib.optional (
            a < b && net.cidrsOverlap (subnetOf labA) (subnetOf labB)
          ) "${a} (${subnetOf labA}) overlaps ${b} (${subnetOf labB})"
        ) labDefs
      )
    ) labDefs
  );

  # Every host port a lab binds, read off the services it runs.
  #
  # The claim is about what two labs on one host do to each other, so the
  # evidence is what they publish rather than which options were set. It was
  # five `lib.optional <feature>.enable` branches naming the option each port
  # comes from — one per host floe, restating the placement condition, and one
  # of them restating it wrong: the https port is bound exactly when the lab
  # holds a root to terminate with, which was spelled `link.provides ? ca`.
  # That tested for a *unit named* `ca`, so a lab placing its root under any
  # other name published 443 and claimed nothing.
  #
  # A publication is `[<address>:]<host>:<container>[/<proto>]`, and it claims
  # the host port unless its address is on the lab's own bridge — that network
  # is the lab's and two labs have different ones. Both other forms claim it:
  # `127.0.0.1:8088:80` binds loopback, and a bare `5353:53` binds every
  # interface, which is the wider claim rather than no claim. The old list
  # could not tell those apart; it had one entry per option, and the option
  # said nothing about which addresses the container would answer on.
  portsOf =
    lab:
    lib.concatLists (
      lib.mapAttrsToList (
        service: svc:
        lib.concatMap (
          spec:
          let
            parts = lib.splitString ":" spec;
            addressed = lib.length parts == 3;
            hostPort = lib.elemAt parts (if addressed then 1 else 0);
            protoParts = lib.splitString "/" spec;
          in
          lib.optional (!addressed || lib.head parts == "127.0.0.1") {
            what = "${service} (${spec})";
            port = lib.toInt hostPort;

            proto = if lib.length protoParts == 2 then lib.elemAt protoParts 1 else "tcp";
          }
        ) svc.ports
      ) lab.services
    );

  claims = lib.concatLists (
    lib.mapAttrsToList (name: lab: map (p: p // { lab = name; }) (portsOf lab)) labDefs
  );

  portClashes = lib.concatLists (
    map (
      claim:
      let
        port = claim.port;
        holders = lib.filter (c: c.port == port && c.proto == claim.proto) claims;
      in
      lib.optional (lib.length holders > 1) (
        "host port ${toString port}/${claim.proto} is claimed by "
        + lib.concatMapStringsSep ", " (h: "${h.lab}'s ${h.what}") holders
        + ".\n    Every allocation is derived from the lab's name "
        + "(lib/allocation.nix), so two labs collided on slot "
        + "${toString (lib.mod port 256)} or one was overridden by hand. "
        + "Free slots: ${
          lib.concatMapStringsSep ", " toString (
            lib.take 3 (lib.filter (s: !(lib.elem s (map (c: lib.mod c.port 256) claims))) (lib.range 0 255))
          )
        }."
      )
    ) (lib.unique (map (c: { inherit (c) port proto; }) claims))
  );

  # A hostname with a public route rendered in a cluster, that no floe in that
  # cluster claimed.
  #
  # The two facts are the routes a cluster's bundles render and the
  # `ROUTE_CLAIM`s its gateway collected, and `routedHosts` is the second
  # one — the ingress's host map is built from the claims, keyed by cluster.
  # So this compares what a cluster renders against what the lab will answer
  # for it, which is the comparison the failure is about.
  #
  # It read the cluster's exported `HOST_EXPOSURE` off the lab's link. Same
  # set, one step earlier, and reading it through the document means the check
  # cannot pass on an export the ingress then dropped.
  #
  # Only clusters the lab fronts, which is what being in the map means. A
  # cluster that is its own edge routes its hostnames itself and its rendered
  # routes are nothing the lab answers for; a lab with no ingress answers for
  # none of its clusters, and an unclaimed route there is no worse off than a
  # claimed one, because nothing on the host reaches either.

in
{
  lab-subnets =
    refuse "lab-subnets"
      "Two labs whose docker networks overlap cannot be up at once, and the second one to start fails on an address the first already has."
      subnetClashes;

  lab-host-ports =
    refuse "lab-host-ports"
      "Two containers cannot bind one host port. Everything else about a lab is named after it and does not clash; the ports are the one thing a lab has to be given on purpose."
      portClashes;
}
