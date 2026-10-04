# Evidence-Bound Self-Improvement Research

## Scope

The eleventh collaborative-evolution increment connects the existing mechanisms
into a persistent research campaign. It does not add another model loop,
background timer, deployment system, or UI. Android cloud and managed Desktop
members receive the same contract through the existing scoped recall bridge.

The sequence is evidence-driven, not a fixed number of steps:

1. Inspect original failures or measured bottlenecks.
2. Preserve a diagnosis with alternative causes and observable probes.
3. Select learning in a saved agenda, including uncertainty and resource tradeoffs.
4. Register a self-research cycle linked to a goal-bound innovation opportunity.
5. Dispatch ordinary DAG work, creating alternatives and controlled experiments.
6. Independently review results, negative outcomes and old-capability regressions.
7. Adopt protected scoped versions, reject, revise, or wait with evidence.
8. Register further cycles using the previous review and explicit new information.

These are available capabilities, not required sequential stage counters. Peers
can explore alternatives in parallel, branch from a prior review, and add useful
work while unrelated tasks are still running. Existing permissions, dependencies,
capacity, user pause/stop and qualified goal acceptance remain authoritative.

## Records

`self_research_cycle` is immutable. It pins the diagnosis, diagnosed gap, selected
learning agenda option, innovation opportunity, question, component, scope,
success test and tradeoff with the original goal. The opportunity must cite that
gap or diagnosis. A continuation cites an exact prior `self_research_review` for
the same original goal and states its new information. Cross-goal reuse still
requires explicit transfer/applicability evaluation.

An innovation binds `self_research_cycle` as well as its existing opportunity.
The cycle lineage cannot be removed or reassigned by revising that innovation.
The experiment plan, original tool measurements, innovation assessment, retained
lesson and capability bank remain the existing contracts, not new weaker copies.

`self_research_review` is an immutable independent checkpoint:

| Decision | Required meaning |
| --- | --- |
| Adopt | Measured, independently retained candidates, each with a current protected capability channel |
| Reject | Actual experiment results and rejected learning decisions; originals remain available |
| Revise | Preserve incomplete/negative evidence and a new question, without claiming adoption |
| Wait | Original blocker evidence, observable resumption condition and checked alternatives |

Each reported result must belong to this cycle and have its exact learning
decision. Reviewers cannot be the cycle proposer, candidate/plan author or trial
executor. They must cite and read every original trial observation. Adoption can
retain several candidates, but cannot borrow another cycle's result, omit a
retained candidate's protected selection, or call a rollback awaiting regression
checks an improvement. Rejected alternatives remain in the same review.

The scope of `improvement_verified` is only the registered measurements. It does
not certify global scientific novelty, harness correctness, model intelligence,
physical validation or completion of the original user goal.

## Actual Execution And Recovery

Attach `self_research:{cycle,action_id,why_now}` and the existing
`innovation_work` to an ordinary goal/live work item. Admission verifies the
original goal, opportunity, exact cycle and candidate identity. The host binds
the member, assignment and phase and atomically stores the claim with the DAG.

The stable pair `(cycle digest, action_id)` can have only one work ID. Recovery
reuses the claim; changing the task name cannot bypass duplicate-effect
protection. A materially new experiment uses a new registered action and plan.
Existing worker checkpoints preserve the exact context after process death.

Terminal outcomes store node/work identity, timestamps, output digest and
truncation, never a fabricated capability score. Existing incremental planners
see them when new evidence arrives, and the normal goal controller sees them at
the next checkpoint. A failed research action does not stop independent branches.
Saved observations are reused after reconnect, instead of rerunning completed
tools to obtain a lost receipt.

A wait record does not itself pause a team. The coordinator keeps feasible work
moving and uses existing resource/permission blockers when nothing executable
remains. No retry count or research-round count declares success. Conversely,
this contract does not authorize unrelated perpetual research after the user's
goal ends or is stopped.

Ordinary tasks use the no-workspace-I/O fast path. The ledger, encrypted workspace,
scope isolation, artifact paging and existing runtime own persistence. There is
no polling while idle and no dependency on a page remaining open.

## Boundaries And Remaining Acceptance

This is scoped workflow/procedure/tool research. The existing Agent Evolution Lab
remains a separate evaluation runner, and global self-evolution/shadow-release
approval is not bypassed. No model weights or global app code are rewritten by
publishing these records.

Local synthetic tests can establish contract enforcement, actual DAG dispatch,
idempotence, original-evidence binding and encrypted reopen. They cannot establish
that a real model chooses valuable questions, reliably designs correct harnesses,
improves itself over months, or exceeds a single Agent at equal cost. Those remain
separate real-model, long-duration and independently replicated evaluations.

## Research Context

The [Darwin Goedel Machine paper](https://arxiv.org/abs/2505.22954) motivates an
archive of empirically evaluated alternatives instead of discarding every
non-winning attempt. This implementation uses that idea for scoped evidence and
method history, not unapproved self-modifying deployment.

[Anthropic's agent evaluation guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
motivates checking full execution trajectories and outcomes, not merely fluent
final text. Here, terminal dispatch status is explicitly distinct from controlled
measurement, independent retention and original-goal acceptance.
