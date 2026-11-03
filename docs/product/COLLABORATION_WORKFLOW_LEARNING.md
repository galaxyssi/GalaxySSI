# Evidence-Bound Workflow Learning

Capability 9 connects saved method hypotheses to the existing collaboration scheduler. It does
not create a second agent runtime, change the UI, call models when idle or replace goal criteria.

## Method Versions

`workflow_method` is an immutable scoped workspace record. It describes its domain, suspected
bottleneck, rationale, applicability, risks, falsifier, roles, required inputs and executable DAG.
Improvement dimensions are decomposition, retrieval, tool use, collaboration and verification.
Each step uses the existing stage, assignment, dependency policy and independent-review contract.

Changed methods use a new object, `previous_method` and preserved feedback references. Feedback
can include failure experiences, diagnoses, measured experiments, prediction errors or artifacts.
An artifact is not automatically measured evidence. The method starts as an **unverified candidate**.
There is no fixed number of steps or iterations deciding when the original goal is complete.

## Actual Dispatch

The coordinator emits ordinary work entries for every step, with:

```json
{
  "id": "trial-a:parse",
  "member": "authorized-person-id",
  "stage": "EXECUTE",
  "assignment": "Exact assignment from saved method",
  "depends_on": [],
  "workflow_step": {
    "execution_id": "trial-a",
    "method": {"object_id": "saved-id", "revision": 1, "sha256": "host-digest"},
    "step_id": "parse",
    "inputs": {"dataset": {"object_id": "input-id", "revision": 1, "sha256": "host-digest"}}
  }
}
```

The host admits the whole method atomically: exact method and inputs, all steps, consistent roles,
existing authorized people, exact assignments and dependencies, and independent reviewer identity.
It cannot omit a check or silently change an admitted method. Inputs remain untrusted data. A
method cannot recruit, choose a new model, expand permissions or bypass native-tool policy.

Both next-round and live planning attach these bindings to real worker contexts. Normal provider
adapters execute the same graph, including remote Desktop members. Unrelated work does not acquire
new dependencies. Completed work keeps its identity on replay; the existing scheduler filters it
out before dispatch. Incomplete or malformed new graphs return actionable planning feedback.

New workflow dispatches currently require existing roster members. Recruit in a preceding normal
planning checkpoint before assigning them workflow roles. Ordinary work has no added workspace I/O.

## Feedback And Comparison

The existing durable run context retains admitted identities and original terminal member status,
start/completion times, output digests and truncation flags. Invalid/missing elapsed time is null,
not zero. Failed work is retained. Reopening/replaying does not recalculate old timing. Timing is
attempt wall time, not isolated model/tool time, CPU consumption, cost or a quality score.
Device replay also exposed the member-context allowlist dropping the new workflow binding and
the earlier action-prediction binding. Both exact internal keys are now preserved; arbitrary
`collaboration_workflow_*` or `collaboration_prediction_*` keys are still rejected.

For a controlled comparison, preserve old and new `innovation` records with exact
`workflow_method` references. Register `experiment_plan.workflow_comparison` with the dataset,
controlled conditions, quality oracle, cost accounting and selection bias. Target and regression
cases are mandatory. Original measurement samples must match the saved method and dataset digests.
Existing arithmetic checks, source/time/version checks, full-read evidence and independent lesson
retention still apply. Faster but less correct is not a retained improvement.

Reports are original tool outputs, not model prose, but a harness can still emit misleading
numbers. These fields do not prove the harness executed the production graph. Host dispatch
outcomes are separately available for inspection; external independent harness review and real
workload evaluation are still required. No automatic global rollout is added by this increment.

## Acceptance Boundary

Synthetic tests verify graph admission, actual scheduler/context integration, recovery, negative
paths and comparison integrity. They do **not** prove autonomous model optimization, scientific
discovery, safe generated tools, long-term capability retention or superiority over a single agent.
The user has not authorized real model calls for this increment.

## References

- [AFlow](https://arxiv.org/abs/2410.10762): code-represented workflow search using execution feedback.
- [AutoFlow](https://arxiv.org/abs/2407.12821): iterative workflow optimization.
- [Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents):
  evaluator/optimizer and orchestrator/worker patterns with clear feedback.

These motivate executable versions and measurable feedback, not a claim to reproduce their results.
