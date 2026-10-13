# Images and Registries

Two concerns: getting images onto a machine that may not have internet, and
knowing what a lab references at all.

## What a lab references

```bash
cata --flake .#<lab> images list                 # everything the lab references
cata --flake .#<lab> images prefetch             # pull it all into the cache
cata --flake .#<lab> images prefetch --dry-run
```

`images list` reads `images.txt` from the rendered package, which is
extracted from every pod template at build time, so it covers init
containers and CronJob templates too, not just the obvious ones.

A floe that claims its image set is exhaustive says so, and
`images-complete-<lab>-<cluster>-<floe>` holds it to that by scanning the
rendered output for an image the floe did not declare.

## Local registry

```nix
units.registry = floes.lab-registry { };
```

Runs a [Zot](https://zotregistry.dev/) pull-through cache as a host service.
The plan writes `registries.yaml` and `certs.d` into each cluster so pulls
route through it transparently.

Placing the floe is the whole of saying the lab runs one. A provisioner that
cannot mount a containerd config declares no `OCI_MIRROR` hole, and a lab
that places a cache no cluster can pull through is refused by name rather
than running a cache nothing consults.

Worth it for two reasons: `lab destroy` followed by `lab up` does not
re-download several gigabytes, and a lab keeps working on a bad connection.

## Mirroring

```bash
cata --flake .#<lab> images mirror --registry registry.example.com/lab
```

Copies every image the lab references into a registry you control, using
`crane`. For air-gapped installs, or for not depending on Docker Hub rate
limits in CI.

## Pinning policy, and what is not here

The `image-pin` [lint rule](./lint.md) reads two fields out of
`metadata.json` — `requireDigest` and `allowedRegistries` — and both are
emitted empty by `lib/lower/lab.nix`. Nothing sets them, so the rule reports
nothing today.

That is a gap and not a design: the rule and its plumbing exist, and what is
missing is where a deployer says so. Until it is somewhere, pin by writing
the digest into the floe's own input, which is the place a version belongs
anyway:

```nix
grafana = floes.grafana { image = "docker.io/grafana/grafana@sha256:abc123…"; };
```

Per-resource exemption, where a rule is genuinely wrong about one object:

```yaml
metadata:
  annotations:
    catallaxy.io/lint-skip: image-pin
```

Building and publishing an image the lab itself produces is likewise not
implemented. It was documented here as `lab.images.publish.<name>` with a
`publish-images` step; no such option and no such step kind exist.
