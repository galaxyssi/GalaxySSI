# Evolution observation checkpoints

Experimental readiness: the original single-field commit-message counterexample is
now correctly rejected, but compound semantic verification is still unreliable.
The live OR control was incorrectly treated as AND, and another rejection cited
the wrong field. Do not merge or deploy automatic retirement from this increment.
See the completion verification report for the failed live controls.

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

## Field-scoped publication review

Before the broad retirement review, each publication-related requirement gets
an independent field-scoped review:

1. A local scope compiler receives the complete requirements and a host field
   directory with field meanings, but no observed values or previous verdicts.
2. It selects the minimum evidence fields for each requirement. A missing source
   is represented by an empty selection, not an invented observation.
3. A separate inference context receives one complete requirement and only the
   selected observed values. It cannot see neighboring fields, the compiler's
   explanation, the planner's proposed verdict, or another criterion's review.
4. The host checks every quotation against the selected source. A pass must
   quote every selected field; fabricated or out-of-scope quotations are invalid.
5. Failed or inconclusive field reviews stop retirement and persist their actual
   cause for later replanning. They cannot be overridden by a broad positive
   explanation. Only all-pass scoped reviews proceed to broad verification.

Field meanings are host schema metadata, not keyword routing or hardcoded
semantic verdicts. For example, `base_ref` means the actual destination branch;
`files` is the complete changed-file list, not the document contents. A PR body
contains claims, not independent evidence of reviewer approval or changed files.
This initial catalog covers publication evidence; arbitrary implementation facts
still need their appropriate evidence adapters, not substitution by PR prose.

Experimental compound handling classifies each selected field, binds proposed
mandatory clauses to original token ranges, and independently reviews their
necessity before isolated checks and a final joint assessment. Source indexing
preserves original wording; it does not translate requirements or implement
keyword-based task routing. Per-field progress is persisted as inconclusive
until the joint requirement has an outcome. This source-grounding machinery
does **not** establish reliable Boolean semantics: the current local model has
misclassified alternative conditions as mandatory despite an independent review.
That failing control remains a release blocker, not an accepted limitation to
silently bypass. Verification requests explicitly use temperature zero; ordinary
planning requests retain their existing sampling defaults.

The independent necessity reviewer no longer receives the compiler's reasons
or token-index table. It tests whether the full requirement can remain true
when a proposed condition is false; needing to read a field is not the same as
requiring its condition to hold. Verification schemas request observations
before the final verdict, without changing the strict evidence checks.

A rejected semantic compilation supplies its source-only assessment and actual
review feedback to one correction inference. The corrected proposal receives a
fresh independent review that cannot see the prior feedback. Repeated rejection
retains both reviews and remains inconclusive. This bounded compiler correction
is not a lifetime action limit and cannot grant publication or task retirement.
Stopping the planner is checked before each inference. All admitted guards are
observed even after a failed guard so a misleading early failure cannot hide
the remaining evidence; a failed guard still prevents broad acceptance.

Each result is checkpointed and audited as it arrives. Disabling the planner
between inference stages prevents the next model call. Graph identity and all
publication evidence are rechecked before a verified revision is applied.
The cache contract is versioned so an old unrestricted review cannot admit a
new automatic batch. Semantic accuracy remains model-dependent; strict source
quotation is necessary evidence validation, not a proof of arbitrary reasoning.

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
The planner now observes this state through the scheduled final verifier described
in `evolution-final-verification.md`, with fresh evidence and a locked completion
transition. This scheduling integration does not qualify the known unreliable
semantic verifier for production deployment.
The opt-in `tools/testing/verify_local_campaign_completion.py` harness also performs
a fresh original-goal review using immutable candidate contents, re-evaluated
literal/preservation checks, actual publication text and fresh integration CI.
Its `--finish` flag records coordinator completion only after the review passes
and the graph/evidence remain unchanged. This is an explicit verification
harness; scheduled runtime verification is implemented separately in the planner.

The original goal is distinct from criteria added by a generated plan. A review
must not pretend that a generated criterion was satisfied merely because it is
unnecessary for the original goal. Such excess requirements need goal-level
replanning; a commit-message requirement cannot be satisfied using a PR body.

Private inference remains on a literal loopback endpoint. No production
scheduler is enabled, cloud provider selected, or device state reset by this
change. Checkpoint decisions do not add a total action budget.
