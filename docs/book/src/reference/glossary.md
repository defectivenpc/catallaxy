# Glossary

One line each, in roughly the order you meet them. The last column names
where the term is actually explained, which is the only place that
explanation is maintained.

Most of these words are borrowed from Haskell's Backpack and from ML
modules; [The Model](../understanding/model.md#where-the-words-come-from)
has the mapping and says why the rules follow from it.

## The nouns

| Term              | Means                                                                                                                                              | Explained in                               |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| **Lab**           | Everything: your clusters, the host services supporting them, your secrets, and the plan that builds it all. One `mkLab`, such as `minimal.local`. | [The Model](../understanding/model.md)     |
| **Base**          | `minimal`, which is not a lab. It takes an env and yields one, the way `List` is not a type but takes one to make `List Int`.                      | [Configure a Lab](../using/configuring.md) |
| **Env**           | What a base is applied to: the part only a deployment knows — subnets, ports, domains, credentials.                                                | [Configure a Lab](../using/configuring.md) |
| **Cluster**       | One Kubernetes cluster inside a lab, at `lab.clusters.<name>`. Mostly an attrset of instantiated floes.                                            | [The Model](../understanding/model.md)     |
| **Floe**          | One capability, as a type signature with an implementation behind it. The definition; it has holes.                                                | [The Model](../understanding/model.md)     |
| **Instantiation** | One use of a floe, at a name, in a cluster. A stack is keyed by the instantiation and not the floe, because one floe can be used more than once.   | [The Model](../understanding/model.md)     |
| **Bundle**        | A group of Kubernetes resources that install together. One floe usually emits several. Reconciled: the cluster is the record of truth.             | [Bundle Schema](./bundles.md)              |
| **Resource**      | A thing created outside Kubernetes, by a tool that plans against recorded state. State-tracked: a state file is the record of truth.               | RFC 0003                                   |
| **Signature**     | A named, typed interface: `API_GATEWAY`, `DNS_ZONE`. What a floe requires and provides.                                                            | [mkFloe API](./floe-api.md)                |

## Shapes a floe takes

Not a taxonomy: there is no `floeKind` field and no category to register in.
A floe is only ever what it declares, and these are the four shapes that
declaring has produced so far.

| Shape                | Declares                                                                                                                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Component floe**   | Requires `KUBERNETES_CLUSTER`, emits `catallaxy.component`. What most people mean by a chart: workloads installed into a cluster. `mkComponentFloe` is `mkFloe` with that one hole pre-filled. |
| **Provisioner floe** | Emits `catallaxy.cluster` — brings a cluster into existence, so it cannot require one.                                                                                                         |
| **Resource floe**    | Emits `catallaxy.resources` and `catallaxy.publications`: infrastructure a state-tracking tool owns.                                                                                           |
| **Lab floe**         | Requires no cluster and answers a signature at lab scope, for the things a lab has one of.                                                                                                     |

## Linking

| Term            | Means                                                                                                         | Explained in                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Provision**   | One named thing a floe provides, as `<instName>/<provide>`. A cluster exposes selected provisions to the lab. | [Configure a Lab](../using/configuring.md)       |
| **Hole**        | A place a floe requires a signature. Named by that signature's `as`, enforced across the whole floe set.      | [mkFloe API](./floe-api.md)                      |
| **Link**        | Matching each hole to the one floe providing that signature. Zero and two are both errors naming the floes.   | [How It Works](../understanding/how-it-works.md) |
| **Sealing**     | Cutting a provided value down to its signature's fields, so a consumer cannot read an implementation detail.  | [How It Works](../understanding/how-it-works.md) |
| **Scope**       | What a cluster resolves against: its own floes, then what the lab exposes. Nearer wins.                       | [Configure a Lab](../using/configuring.md)       |
| **Local**       | A signature field that does not cross a cluster boundary. Per field, not per signature.                       | [mkFloe API](./floe-api.md)                      |
| **Elaboration** | Turning a link result into a cluster picture: bundles, ordering edges, ops, lint.                             | [How It Works](../understanding/how-it-works.md) |

## Ordering

| Term       | Means                                                                                                                | Explained in                                     |
| ---------- | -------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Wave**   | A set of bundles that can install at the same time, because none is waiting on another. Computed, never written.     | [How It Works](../understanding/how-it-works.md) |
| **Token**  | A short string meaning "this is ready". Arbitrary: only the matching matters. Derived, not written by a floe author. | [How It Works](../understanding/how-it-works.md) |
| **Anchor** | "Install me after that", where "that" is named directly rather than through a token.                                 | [Anchors and Tokens](./anchors.md)               |
| **needs**  | The one ordering field a floe author writes. Sibling bundles **in the same floe** and nothing else.                  | [Write a Floe](../using/writing-a-floe.md)       |

## Building and running

| Term            | Means                                                                                                   | Explained in                                     |
| --------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| **Plan**        | The ordered list of steps that builds or destroys a lab. `lab plan` prints it, `lab up` runs it.        | [How It Works](../understanding/how-it-works.md) |
| **Step**        | One entry in that list.                                                                                 | [Plan Step Kinds](./step-kinds.md)               |
| **Output kind** | What a floe emits: `catallaxy.component`, `.cluster`, `.resources`, `.publications`.                    | [mkFloe API](./floe-api.md)                      |
| **Stack**       | A set of resources planned and applied as a unit, keyed by the instantiation and the phase.             | RFC 0003                                         |
| **Publication** | A value a stack writes into one of the lab's secret stores, for another cluster to subscribe to.        | RFC 0003 §7                                      |
| **Projection**  | One key from an encrypted lab secret, placed into a Kubernetes Secret in a named cluster and namespace. | [`lab.secrets`](./options.md)                    |

## Cloud labs

| Term      | Means                                                                                              | Explained in                  |
| --------- | -------------------------------------------------------------------------------------------------- | ----------------------------- |
| **Edge**  | Where a cluster is reached from. `proxy` (the lab's ingress), `self` (its own address), or `none`. | RFC 0005 §6.4                 |
| **Owner** | Which tool is responsible for a bundle, and when.                                                  | [Bundle Schema](./bundles.md) |
| **Drift** | A field something other than your CD tool writes, such as a webhook filling in a CA certificate.   | [Bundle Schema](./bundles.md) |

## Words that used to mean something else

If you have older notes or an out-of-date branch:

| Term             | Now                                                                                                                                                                                                               |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **exports**      | gone. A floe `provides` a signature; consumers `require` it and get a sealed value.                                                                                                                               |
| **enable**       | gone. A floe is instantiated by being in `lab.clusters.<c>.floes`, or it is not there.                                                                                                                            |
| **requiresMany** | replaced by `requiresOptional` (zero or one). The fan-in carried no ordering.                                                                                                                                     |
| **appliance**    | never shipped. A lab's host services are `lab.{dns,registry,proxy,egress}`.                                                                                                                                       |
| **camp**         | gone. Say **bundles** and **resources**; when the model matters, they are _reconciled_ and _state-tracked_. RFC 0002 and RFC 0003 still say "camp" because an RFC records what was decided, not what is true now. |
| **promise**      | a **provision**. The option was always `provides`; only the prose said "promise".                                                                                                                                 |
| **offer**        | a cluster **exposes** a provision to the lab.                                                                                                                                                                     |
| **unit**         | an **instantiation**. In Backpack a unit is the definition, which is what this calls a floe, so the word was doing the opposite job.                                                                              |
