# Plan Step Options

Steps you declare yourself, at `lab.steps.<name>`. What each `kind` accepts in `params` is in [Plan Step Kinds](../step-kinds.md).

| Option | Type | Default |
| --- | --- | --- |
| [`after`](#after) | `list of string` | `[ ]` |
| [`before`](#before) | `list of string` | `[ ]` |
| [`cluster`](#cluster) | `null or string` | `null` |
| [`description`](#description) | `string` | `the attribute name` |
| [`direction`](#direction) | `null or one of "deploy", "teardown"` | `null` |
| [`kind`](#kind) | `string` |  |
| [`origin`](#origin) | `string` | `"lab"` |
| [`params`](#params) | `attribute set` | `{ }` |
| [`provides`](#provides) | `list of string` | `[ ]` |
| [`teardown`](#teardown) | `null or value "before-cluster-destroy" (singular enum)` | `null` |
| [`policy.interactive`](#policy-interactive) | `boolean` | `false` |
| [`policy.onFailure`](#policy-onfailure) | `one of "fatal", "continue"` | `"fatal"` |

## Top level

### `after` {#after}

Anchors this step follows. `provides:<token>` waits on whatever
publishes it, `kind:<kind>` on every step of that kind, and
`optional:` either tolerates matching nothing.

`optional:` is not a weaker edge — it is the difference between
"after the DNS server, if this lab runs one" and "this lab must
run a DNS server".

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/planner

---
### `before` {#before}

Anchors this step precedes. Inverted into `after` edges on the
other side, so a step can insert itself ahead of something that
has never heard of it.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/planner

---
### `cluster` {#cluster}

Cluster this acts on, when it acts on one.

**Type:** `null or string`

**Declared in:** modules/lab/planner

---
### `description` {#description}

One line, shown by `cata lab plan`.

**Type:** `string`

**Default:** `the attribute name`

**Declared in:** modules/lab/planner

---
### `direction` {#direction}

Which plan it belongs to. Null takes the kind's, when the kind
runs in exactly one — most do, and saying it twice is a way for
the two to disagree.

**Type:** `null or one of "deploy", "teardown"`

**Declared in:** modules/lab/planner

---
### `kind` {#kind}

Which of the 34 step kinds this is. The kind decides what params
are legal, whether the step may run in a given direction, and the
retry class the executor applies.

**Type:** `string`

**Declared in:** modules/lab/planner

---
### `origin` {#origin}

Who declared it, for an error message to name.

A floe's steps are stamped with the floe, because "step
`mesh-join` names an anchor nothing provides" is not actionable
without knowing which floe to open.

**Type:** `string`

**Default:** `"lab"`

**Declared in:** modules/lab/planner

---
### `params` {#params}

Payload for the step kind, checked against its schema.

**Type:** `attribute set`

**Default:** `{ }`

**Declared in:** modules/lab/planner

---
### `provides` {#provides}

Tokens that are true once this step has run.

**Type:** `list of string`

**Default:** `[ ]`

**Declared in:** modules/lab/planner

---
### `teardown` {#teardown}

A moment in the teardown, for a step a floe contributes. The
planner turns it into the anchor, because it knows which cluster
the floe is on and the floe does not — that is the whole point.
A floe naming a plan token would be depending on lab internals
the signatures exist to keep it away from.

**Type:** `null or value "before-cluster-destroy" (singular enum)`

**Declared in:** modules/lab/planner

---
## `policy`

### `policy.interactive` {#policy-interactive}

The step cannot finish without a human.

Two consequences. It makes the lab ineligible for the e2e runner, via
`lab.out.selfContained`. And it suppresses the retry its kind's
idempotency class would otherwise get: re-running a step that opens a
browser issues a fresh prompt while the first is still waiting, so the
retry defeats the step it is retrying.

**Type:** `boolean`

**Default:** `false`

**Declared in:** modules/lab/planner

---
### `policy.onFailure` {#policy-onfailure}

Whether the run stops here.

`continue` is for teardown, where a step that cannot finish must not
strand the ones after it — a cluster that is already gone should not
prevent removing the network it was on.

**Type:** `one of "fatal", "continue"`

**Default:** `"fatal"`

**Declared in:** modules/lab/planner

---
