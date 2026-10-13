# A hostname is claimed, and the gateway owns the claim

A floe that publishes a public hostname **provides** a `ROUTE_CLAIM`. The
gateway **collects** them and provides one `HOST_EXPOSURE` for the cluster,
which the cluster exports and the lab's host floes collect. The resolver and
the ingress read that, and nothing reads a cluster's elaborated output to
find out what it serves.

What forces this is a cycle. A host service is a floe now, and its content
depends on what the clusters expose: the zone file carries one record per
routed hostname when the lab fronts only some of its clusters. Computing
that from `cluster.out` and handing it to the floe as an input is
`infinite recursion` — `lab.units` has to be known before the link exists,
and the exposure facts only exist after it. A unit of a link cannot be
computed from that link's output.

`collects` is the way out, and the reason is the fixpoint: a collection is
resolved _inside_ the link, and a body runs after resolution. So the host
floe stops depending on the clusters for its inputs and reads a collected
value in its body, which is the ordinary case the linker already handles.
This is the same shape the floe interface's own NixOS example uses, where
`networking` collects a `PORT_CLAIM` from every service and owns the
firewall namespace.

The gateway owns it because it already half did.
`policies.promisedHostsAreRouted` identifies a gateway by `baseDomain` and
`parentRef`, then scrapes `https://host…` strings out of every _other_
unit's provides to check they are routed. The identification is the part
this takes over; the scrape stays, for a reason given under Consequences.

## Considered options

**A dedicated exposure floe in each cluster** that collects the claims and
provides the aggregate. Rejected because it is a unit whose only job is to
satisfy a mechanism. The gateway is the thing that owns the hostname
namespace — a namespace with an owner is the shape the floe interface
recommends, and this one has an owner already.

**Keep deriving it from rendered routes.** `elaborate.nix` scans every
bundle for `HTTPRoute` and `TLSRoute` resources, and
`modules/lab/host/proxy.nix` says why that is good: "The elaborator already
read these off the rendered routes, so there is no list to keep in step with
the manifests." Rejected because the derived fact arrives too late — it is a
product of elaboration, which runs on the link's output, so anything reading
it cannot be in the link.

**Mark the aggregate `T.derivedFrom ROUTE_CLAIM` and keep the scan as the
source of truth**, so a claim that disagrees with a rendered route is
refused. Not taken now, and the reason is scope rather than doubt: it needs
the scan and the claims to be compared, which is a second mechanism, and the
claim has to exist first. Worth reopening once the claims are in — the
property it buys back is the one this decision gives up.

## Consequences

**A hostname becomes something a floe says rather than something the
manifests show.** That is the real cost. A claim can disagree with the route
a floe renders, where a scan could not, and nothing catches the disagreement
yet. Two things reduce it: `lib/floe-catallaxy/component.nix` has one route
constructor, `mkRoute`, which every routed floe already calls — so the claim
and the route come from the same expression in the same body — and the
gateway's own lint checks (`route-hostname-in-zone`,
`route-listener-exists`) still run against what rendered.

Nine floes gain two lines each: `provides.route = sigs.ROUTE_CLAIM` in the
header and the value beside the `mkRoute` call. They are `custom`,
`grafana`, `netbird`, `harbor`, `forgejo`, `podinfo`, `gateway`, `argocd`
and `kanidm`.

`kanidm` is the ninth and it was found the hard way, which is worth
recording because it is exactly the cost named above. It renders no route at
all — kaniop builds the `HTTPRoute` from `spec.gateway` — so it carried a
`routedHosts` escape hatch to tell the elaborator's scan about `idm.<zone>`.
The scan fed the ingress and the claims fed the resolver, so for as long as
those were two mechanisms the hostname was routed by HAProxy and answered by
nothing. `checks.lab-routed-hosts-are-claimed` is the law the third option
above asked for, in the direction that was affordable: every public route a
fronted cluster renders must be a hostname some floe in it claimed.

## Where the address comes from

Settled after the fact, and it splits one field across two owners.

**The provisioner declares where a cluster is dialled**, as a `CLUSTER_EDGE`
it provides: `k3d-<instance>-server-0` on 80 and 443,
`<instance>-controlplane-1` on the gateway NodePorts, nothing at all from
`external-cluster`. Every one of those is the container-naming convention of
the tool that created the cluster, so there is nowhere else the answer can
live — and a cluster nobody here created declining to answer is the complete
answer, not a gap.

**The deployer decides whether this lab fronts it**, by whether the cluster
exports its `HOST_EXPOSURE`. So `edge.mode` does not become an input and
does not travel: it was a flag that had to agree with an export, and the
export says it.

The address travels _inside_ the aggregate rather than as a second
collection, because a route needs the hostnames and the address together and
nothing downstream can pair them — exposures are keyed by cluster and edges
would be keyed by its claim. The gateway takes `optional.edge` and carries
it through; the lab binds that hole to the same claim unit it binds
`requires.claim` to, since the lab is what knows which claim answers which
cluster.

A lab that exports an exposure its provisioner gave no address for is
refused, naming the cluster. That combination is the only mistake available
here: a cluster with no address is the ordinary case for a managed one, and
asking the lab to route to it is the error. `checks.lab-edge` holds both
sides.

`lib/eval/exposure.nix` and `lab.edges` both delete, and so do `EdgeSpec`
and `EdgeMode` in the CLI. The proxy is `floes.lab-proxy` now, collecting
what it routes; the document carries `routedHosts` — every hostname the lab
answers for, keyed by the cluster that serves it, read off the same exported
exposures the ingress builds its `use_backend` lines from.

`cata lab verify` was the last reader of the mode, and it asks a better
question now. It filters per _hostname_ rather than per cluster, because the
host map is what the ingress was built from: a cluster absent from it is a
cluster the lab does not front, and a hostname absent from a fronted
cluster's entry is one nothing claimed. The second case was unreachable
before — the mode could only say something about a whole cluster — and it is
the kanidm failure, so `verify` would have probed `idm.<zone>` through an
ingress with no backend for it and blamed the workload for the 503.

The string-scraping half of `promisedHostsAreRouted` stays, because it
turned out to be about something else — a promise is a `https://host` in a
_signature_, not a route, and checking those against routes is a property
the claims do not subsume.

`exposedHosts` stays, because the cluster document carries it for
`cata lab verify` — it is a cache of what the waves say, which is a thing
with a law attached rather than a second source of truth, and
`lab-routed-hosts-are-claimed` is now that law.
