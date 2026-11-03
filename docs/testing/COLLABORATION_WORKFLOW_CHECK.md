# Workflow applicability inspection

## Purpose

Members can inspect a saved conditional method before committing work. The new
`collaboration_recall` mode `workflow_check` is exposed through the existing
Android native, managed cloud and Desktop Codex tools. It does not introduce a
second planner or change already admitted workflow decisions.

```json
{
  "mode": "workflow_check",
  "object_id": "<exact saved rule ID>",
  "revision": 1,
  "sha256": "<exact saved rule digest>",
  "inputs": {"data": {"count": 3}}
}
```

Use a `workflow_selection_rule` linked to a retained comparison, not a method
reference. Inputs may be partial but must use the method's public input names.
The host checks current lineage and assignment visibility. The existing remote
recall envelope is 4096 UTF-16 characters; pass compact condition data, not files
or logs. This bounds a control message, not the number of research steps.

## Feedback and use

The paginated result preserves exact rule and baseline/candidate references. Each
condition includes its predicate, rationale, state, actual type and a specific
unknown reason: missing input, unavailable pointer, nonscalar value, type
mismatch, unsupported numeric value or nonnumeric ordering. Null is distinct
from missing data. Strings are not coerced to numbers.

`known_blockers` lists failed prerequisites and matched counterconditions. If one
is already known, filling other unknowns cannot change this rule's selection
while those facts remain fixed. Otherwise `unknowns_may_change_selection` is a
conservative signal to consider further evidence. It is not joint constraint
solving, expected information gain, probe value or a guarantee that a candidate
can become applicable. Unknown predicates can themselves be contradictory.

The Agent chooses whether to acquire evidence, revise the rule or method, use an
alternative, or proceed within a justified scope. There is no forced probe,
retry counter or automatic model call. Existing `observed_inputs` and
`probe_continuation` carry original tool results into actual subsequent work.
Inspection does not produce an original measurement, admit work, change criteria
or add permissions. Declared input values remain unverified. The normal baseline
fallback does not certify that baseline as suitable in a new domain.

Keep the exact reference and inputs unchanged when following `next_offset`.
Current lineage is checked again for each read and for new work. Saved work
recovery still replays its pinned choice. No new workspace publication is made
by inspection; the ordinary tool wrapper may record its read-only invocation.

## Verification scope

- Shared-core tests cover typed unknown diagnostics and unchanged selection.
- Android unit tests exercise exact durable rule chains, decision-relevant and
  irrelevant gaps, current-lineage/assignment isolation, no mutation, no work
  admission and unchanged fallback dispatch.
- Desktop tests exercise compact typed JSON, deep copies, wrong-phone/turn
  response rejection and no evidence-delivery confirmation for this mode.
- A synthetic device test uses normal durable publications and both native/cloud
  readers, verifies store reopen and revoked access, and cleans up its own group.
  It does not call a model, execute a saved method or demonstrate reboot recovery.

On 2026-10-11, 107 focused Android unit tests, 20 shared-core tests and 29 Desktop
bridge tests passed. The app and instrumentation APKs compiled successfully.
Android is 1.4.145 (1230), Desktop source is 1.4.55. The new device test has not
run: an unrelated real collaboration was active, so S20U installation and Desktop
restart were deferred to preserve that work. No real model was called for this
increment. Kotlin size, Chinese-text and Desktop structure checks passed.

A future real
trial must establish whether an Agent actually uses this feedback to choose an
informative action and improve unseen-task results. Availability and synthetic
correctness alone do not establish autonomous learning or team superiority.
