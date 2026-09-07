# Glossary

One line each, in roughly the order you meet them. The last column names
where the term is actually explained, which is the only place that
explanation is maintained.

## The nouns

| Term          | Means                                                                                                                     | Explained in                           |
| ------------- | ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| **Lab**       | Everything: your clusters, the host services supporting them, your secrets, and the plan that builds it all. One `mkLab`. | [The Model](../understanding/model.md) |
| **Cluster**   | One Kubernetes cluster inside a lab, at `lab.clusters.<name>`. Mostly an attrset of instantiated floes.                   | [The Model](../understanding/model.md) |
| **Floe**      | One capability, as a type signature with an implementation behind it.                                                     | [The Model](../understanding/model.md) |
| **Bundle**    | A group of Kubernetes resources that install together. One floe usually emits several.                                    | [Bundle Schema](./bundles.md)          |
| **Signature** | A named, typed interface: `API_GATEWAY`, `DNS_ZONE`. What a floe requires and provides.                                   | [mkFloe API](./floe-api.md)            |

## Linking

| Term            | Means                                                                                                        | Explained in                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------ |
| **Hole**        | A place a floe requires a signature. Named by that signature's `as`, enforced across the whole floe set.     | [mkFloe API](./floe-api.md)                      |
| **Link**        | Matching each hole to the one floe providing that signature. Zero and two are both errors naming the floes.  | [How It Works](../understanding/how-it-works.md) |
| **Sealing**     | Cutting a provided value down to its signature's fields, so a consumer cannot read an implementation detail. | [How It Works](../understanding/how-it-works.md) |
| **Scope**       | What a cluster resolves against: its own floes, then the lab's offers. Nearer wins.                          | [Configure a Lab](../using/configuring.md)       |
| **Local**       | A signature field that does not cross a cluster boundary. Per field, not per signature.                      | [mkFloe API](./floe-api.md)                      |
| **Elaboration** | Turning a link result into a cluster picture: bundles, ordering edges, ops, lint.                            | [How It Works](../understanding/how-it-works.md) |

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
| **Stack**       | A set of state-based resources planned and applied as a unit, keyed by instantiation and phase.         | RFC 0003                                         |
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

| Term             | Now                                                                                    |
| ---------------- | -------------------------------------------------------------------------------------- |
| **exports**      | gone. A floe `provides` a signature; consumers `require` it and get a sealed value.    |
| **enable**       | gone. A floe is instantiated by being in `lab.clusters.<c>.floes`, or it is not there. |
| **requiresMany** | replaced by `requiresOptional` (zero or one). The fan-in carried no ordering.          |
| **appliance**    | never shipped. A lab's host services are `lab.{dns,registry,proxy,egress}`.            |
