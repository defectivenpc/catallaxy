# The artifact this floe's CRD types are generated from.
#
# The *same* pinned thing the floe installs — its `manifest` input defaults to
# this — so the types describe the CRDs that will actually be applied.
#
# A release YAML rather than a chart's `crds/` directory, which is why the
# Gateway API used to be the one source named outside the chart table. Here it
# is not special: the floe owns the manifest, the version and the types.
{ k8sSpecs, ... }:

k8sSpecs.standaloneCrds.gateway-api
