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
