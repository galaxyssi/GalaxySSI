# Evolution observation checkpoints

Draft readiness: the real commit-message counterexample still produces an
incorrect semantic pass. Do not deploy automatic retirement from this increment
until that case is reliably rejected. See the completion verification report.

The campaign scheduler now observes completed work before dispatching the next
ready batch. Initial goal decomposition and failure replanning share an explicit
description of the host-owned candidate, test, publication and integration
lifecycle. Models must not generate extra source-editing tasks merely to repeat
that lifecycle.

## Model decisions

The local planner assesses every ready node as `needs_work`, `satisfied`, or
`inconclusive`, with concrete evidence. The framework derives the action from
these typed assessments; it does not interpret keywords in the reason. This
avoids treating an ambiguous `proceed` response as a request for new execution
when its explanation says the work is already done.

Retiring satisfied work requires a second local model assessment of the task
description and every acceptance criterion. Each must pass and cite completed
nodes. The independent prompt does not contain the planner's reason or verdict.
This is separate inference, not a claim of diversity across independent models.

Publication evidence includes actual GitHub PR title, body, changed files and
head commit message. The host verifies PR identity, merged main destination,
complete file pagination, unique paths and the published head. A URL or a model
claim alone is insufficient. Complete evidence that exceeds the review envelope
is rejected explicitly, never silently truncated into a passing review.

## Durability

- The dispatch callback only reads the persisted decision. It does not call the
  model or GitHub while the scheduler owns a campaign transition.
- Automatic admission does not alter explicit manual `start_ready` operations
  or require an automatic planner for manually advanced campaigns.
- Decisions are tied to the exact DAG observation and a versioned contract.
  Changed graphs and older contracts require a new review.
- Unchanged proceed/wait decisions do not repeatedly invoke the model. Failed
  validation is supplied as observation on a later retry.
- Dispatch is per node: an inconclusive sibling does not block independently
  ready work assessed as still needed.
- Publication evidence and graph identity are checked again after inference.
- Verified retirement is serialized with campaign controls and dispatch. The
  content-addressed proof stores both the observations and independent review.
- Surviving tasks retain their specifications. A retired node's prerequisites
  are inherited by its successors; dependency ordering is not discarded.
- Process death after the graph revision cannot start the retired task or
  apply the retirement again. Disabling planning does not apply an in-flight
  model decision.

## Scope boundaries

Retirement never completes the original goal. A campaign with all remaining
nodes complete stays `awaiting_verification` until final coordinator acceptance.
The opt-in `tools/testing/verify_local_campaign_completion.py` harness performs
a fresh original-goal review using immutable candidate contents, re-evaluated
literal/preservation checks, actual publication text and fresh integration CI.
Its `--finish` flag records coordinator completion only after the review passes
and the graph/evidence remain unchanged. This is an explicit verification
harness, not yet an automatically scheduled final-goal verifier.

The original goal is distinct from criteria added by a generated plan. A review
must not pretend that a generated criterion was satisfied merely because it is
unnecessary for the original goal. Such excess requirements need goal-level
replanning; a commit-message requirement cannot be satisfied using a PR body.

Private inference remains on a literal loopback endpoint. No production
scheduler is enabled, cloud provider selected, or device state reset by this
change. Checkpoint decisions do not add a total action budget.
