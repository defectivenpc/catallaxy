CrossingFloe is too complicated remove unstable option

nix documentation would do better to document input -> output types.

Why does types.raw exist? Why are cluster.floes attrs of types.raw?

colima option is in the cluster.nix file even though it documents itself as
being on the lab.

I think wait timeout would belong on the specific apply process for the
cluster. Wether it is kapp or argo or fleet.

cluster security could be a nested file under cluster/

cluster edge needs to go away or be redesigned

cluster provisions needs to go away. It is a hack that is hardcoding the
idea of crossplane. Lets just.

If possible need to rethink secrets on the cluster. How we get them from
lab, how it publishes them. Perhaps better to redesign with floes
