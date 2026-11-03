# Prospective probe continuations

An action forecast may bind a probe outcome to one or more subsequent workflow
methods and their recipients **before the outcome exists**. This extends the
existing prediction and workflow contracts; it does not introduce an executor,
model call, background trigger or autonomous-success claim.

## Plan before observing

Each `action_forecast.choices[]` may contain `continuations`. This works for both
probabilistic and qualitative forecasts. A branch has exactly these fields:

```json
{
  "id": "recheck",
  "rationale": "A repeated parse contradicts the reuse assumption",
  "when_events": {"one_parse": false},
  "method": {"object_id": "...", "revision": 1, "sha256": "..."},
  "roles": {"worker": "person-a", "reviewer": "person-b"},
  "inputs": {"scope": "current authorized fixture"},
  "observed_inputs": {"measurements": "/measurements"}
}
```

`when_events` maps nonempty registered event IDs to Boolean **measured event
occurrence**: equality with that event's registered expected scalar. It does not
compare a probability or model confidence. Branch IDs are distinct per action.

The method is an exact saved `workflow_method`. Role names match that method and
bind existing member identities, not recruitment aliases. Declared and observed
input names are disjoint and together cover the method's input contract.
`observed_inputs` here is a prospective pointer template, not a fabricated future
observation reference. Its pointers are relative to the forecast's registered
`report_pointer`. Input text remains data, never interpolated instructions.

Multiple branches may match; all matching branches are expanded. This supports
parallel alternatives without a forced winner. A registered branch is not a
validated improvement or a retained capability.

## Admit after measuring

After publishing the existing `prediction_outcome` with original tool checks,
the goal or live planner can submit this work entry:

```json
{"probe_continuation": {"outcome": {"object_id": "...", "revision": 1, "sha256": "..."}}}
```

Only the selected forecast action's branches are eligible. The host reads the
immutable outcome and forecast, resolves one original probe receipt, evaluates
branch conditions, and expands each matching method through normal
`workflow_instance`/`workflow_step` admission. Members, dependencies, review
targets, original inputs, model routing and pause/stop behavior are unchanged.

Failed, missing or out-of-validity fields remain unknown. An unmatched or unknown
result does not dispatch a baseline by default. Admission returns branch-level
states and asks the planner to use ordinary work or a new forecast to obtain
missing evidence, revise its assumptions or choose another approach. That is not
a declaration that the goal failed or that unrelated running work must stop.

Same-round observations require `milestone` with an existing host token granting
the exact original receipt. Existing visibility still applies to the outcome and
forecast. The same source token is passed to all branch steps and independent
review rules remain in force. A continuation never creates access grants.

## Identity and replay

Execution IDs derive from the exact forecast and branch, not the invocation or
outcome-snapshot ID. Repeated admission retains the same work IDs; completed work
is not repeated. Replacing a pinned outcome, method, recipient, input or source
is rejected. Different measurements need a new prospective forecast when they
would change an already admitted branch. New work also checks current lineage.

Workflow task context and durable outcome history retain `probe_origin` with the
forecast, outcome, branch, condition states and that step's recipient mapping (not
a copy of the entire team role map). These fields
record the actual decision path, not measured quality. The host verifies the
original goal/run/turn and criterion at work admission. Large branch sets share
resolution and lineage checks within a plan, rather than rereading the full
probe separately for every branch.

## Evidence boundary

Local fixtures can prove the branch selection, input projection, work admission
and persistence contract. They cannot prove that a model independently authored
a useful probe, that its harness was scientifically valid, or that this improves
quality over a matched-budget baseline. Those require new real-model and external
evaluation runs. This mechanism does not change frozen scientific protocols.
