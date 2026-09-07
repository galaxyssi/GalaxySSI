# Candidate acceptance checkpoints

Desktop 1.0.61 retains an immutable candidate across process restart or
temporary review unavailability. This is a continuation of the same attempt, not
another implementation attempt or an approval to publish.

## Commit boundary

After repository gates pass, the manager stages the candidate and atomically
persists a write-ahead commit intent in the task record. The intent binds the
task, attempt number, managed worktree, branch, pinned base, staged Git tree and
source requirements (including the original campaign goal). It is internal
state and is omitted from public task payloads.

After Git commits, the manager persists the commit identity before any model
review. If the process exits between those steps, recovery reconciles the
intent against Git: the candidate must either still be the exact staged tree
at the base, or exactly one commit above that base with the intended tree.
Changed HEAD, index, unstaged or untracked files, foreign worktrees, changed
requirements and incomplete dependencies block continuation without deleting
the candidate or starting another implementation.

## Recovery and admission

Existing OS ownership and process-quiescence checks still fence recovery. Startup
does not call the model: it verifies the checkpoint and records a proposed
continuation. The normal worker re-runs current repository gates and independent
reviews on the same candidate. Only then may it create an approval hash and enter
`waiting_approval`. Publication retains its existing integrity and CI checks.

An unavailable review preserves the candidate and its checkpoint as blocked
work. An explicit retry or campaign replanning decision can resume it without
calling the implementation Agent again. An exhausted child attempt count does
not reject this continuation, but still rejects a new implementation attempt.
Dependent DAG nodes do not unlock until the existing completion requirements
are met. A cancelled task is not automatically restored.

An inconclusive verdict also preserves the checkpoint: it is not a demonstrated
candidate failure. Coordinator observations include `failure_phase`,
`candidate_verdict`, `candidate_failure_established`, `candidate_commit` and
`retry_effect`. A model decision cannot supersede a retained candidate merely
because its evaluator returned no usable verdict. It can retry validation, add
diagnostic work without retiring the candidate, or wait. This is a state/evidence
precondition, not a classifier of user wording or a forced implementation plan.

Rejected decisions return actionable observations to the planner. Distinct
validation causes survive planner restart for the same graph observation, while
duplicate causes and old response bodies are not accumulated. A changed graph
starts a fresh observation context. Retry and replacement actions must include
an existing node identity; a model's word `retry` alone is not executable.

Concrete semantic rejection or failed current gates return to the existing
failed-attempt/replanning flow. They do not authorize publication. Checkpoint
identity conflicts retain evidence for inspection instead of deleting possibly
external edits. Explicit discard still removes managed candidates.

## Scope of evidence

Tests cover interruption before commit, immediately after the Git side effect,
and during review, including real child-process exit and reopening the stored
task. They assert one implementation invocation, one attempt, stable worktree,
correct commit parentage, no approval before review, dependency gating, current
gate revalidation, unavailable-provider continuation, cancellation, and
preservation of conflicting workspace contents.

These are framework tests with controlled semantic responses, not evidence that
a real model can finish the original campaign. The real private-model repair,
correct acceptance, PR publication, CI repair and merge cycle remains a separate
acceptance target. Atomic task replacement protects process interruption; this
does not claim a tested power-loss guarantee for the host filesystem.

## Local validation results

The initial complete evolution regression passed 429 tests. After the final
retention and cancellation changes, 77 focused checkpoint, semantic acceptance,
durable DAG and legacy lifecycle tests passed in 320.028 seconds. The latest
real process-exit run recovered intent, post-commit and review states in 891.112,
1085.664 and 1589.294 milliseconds respectively. These timings cover state
recovery, not model generation or the entire PR lifecycle.

The 29 Desktop checks, Repository Guard and diff whitespace checks also passed.
The shared Desktop and phones were not restarted or installed during validation.

## Real local-model interruption evidence

A local Qwen3-1.7B Q8_0 worker produced candidate
`063d33c3d64f75deeb58f1380e1746b4c5f067e5` in attempt 3 of the isolated
documentation campaign. The controller terminated the verified worker process
during acceptance review, then reopened the same state. Startup plus recovery
took 2226 ms, preserved the clean worktree and exact commit, and resumed review
at attempt 3 without invoking implementation again. The document was not edited
by the test controller and was not published.

The independent evaluator subsequently invented literals not present in the
original goal. That correctly prevented acceptance, but the coordinator wrongly
interpreted the evaluator error as an implementation failure and replaced the
child. This exposed the missing phase attribution and retirement precondition
described above. A read-only historical replay of ledger sequence 28 reproduced
the wrong replacement even with the improved prompt. Subsequent correction also
omitted `node_id`, demonstrating why a textual retry intention is insufficient
and why previous validation causes must remain in the observation context.

With both distinct validation causes preserved, the same local model returned a
retry targeting the original retained node in 49.685 seconds. It passed the
production decision validator against an in-memory graph projection. The actual
event ledger hash was unchanged. The model's explanation still referred to the
unusable literal check, so this demonstrates executable recovery selection, not
correct independent acceptance or a fully reliable evaluator.

This evidence proves checkpoint recovery and identifies model/planner defects;
it does not prove the complete original-goal acceptance or publication lifecycle.
No replay decision is applied to the current, different live DAG.

The first hosted checkpoint run passed 2338 backend tests but failed the real
process-exit test because its child inherited the Desktop working directory and
could not import the test package. The test now pins the child working directory
to the backend package root; no production recovery behavior or assertion was
removed to fix this CI failure.

Running the complete backend suite from `apps/desktop`, matching the CI entry
point, subsequently passed 2355 tests and 771 subtests with 2 skips in 901.95
seconds. That run started before the final retirement-precondition and feedback
history additions; those additions also passed 30 focused planner/feedback
tests. The complete evolution regression on the final snapshot passed 445 tests
in 411.450 seconds. Its process-exit state recoveries were 930.497, 1173.773 and
1184.484 ms for commit intent, post-commit and review respectively. The final
29 Desktop checks and Repository Guard also passed.
