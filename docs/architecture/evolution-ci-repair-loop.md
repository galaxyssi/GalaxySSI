# Durable evolution CI observation and repair

Desktop 1.0.37 extends the existing technology-radar/proposal/candidate/PR path
with a persistent post-publication CI loop. It does not enable self-evolution,
auto-merge pull requests, weaken candidate gates, or change Android execution.

## Flow

1. A published parent registers a CI watch. Startup also indexes published task
   files, including tasks older than the legacy 500-row listing window. Repair
   children are not indexed as independent watches.
2. A separate observer reads the PR head, paginated check runs and commit statuses
   for that exact SHA, then re-reads the PR. Changed heads, incomplete pages,
   unknown outcomes, and missing checks are never treated as success.
3. Once reported jobs finish with failures, reserve one deterministic repair task
   identity for the parent/head pair in SQLite before creating any child work.
4. The normal evolution Agent inspects diagnostic evidence, changes an isolated
   worktree, and runs the existing scope, review, compile and evidence gates.
   CI logs are explicitly untrusted observations, not Agent instructions.
5. A verified candidate is pushed to the original PR branch without force. It must
   descend from the observed failed head. Closed, forked, or changed PR targets are
   rejected. A candidate already present on the remote reconciles a lost response
   without creating another PR or pushing again.
6. A new PR head receives a new observation and, if necessary, a new repair task.
   Pending CI does not invoke the model. No maximum cumulative CI-head count is
   introduced. A terminal child failure retains its actual error for attention;
   its existing per-candidate retry policy is unchanged.

## Persistence and execution controls

`evolution_ci_watches` resides in the shared Run Kernel SQLite database in normal
Desktop operation. Explicit test stores use a separate database below that store.
Checkpoint events and watch transitions commit together. Unchanged polls update
only scheduling metadata, not a growing stream of heartbeat events.

Workers claim leased watches, reserve child identities before side effects, and
cannot save after losing ownership. A crash after reservation or task-file creation
reuses the same child. Stale callbacks cannot replace a newer watch state. Existing
runtime recovery resets interrupted child execution before the observer resumes it.
Each observer also holds a non-inherited OS file lock during its observation cycle
(Windows `msvcrt.locking`, Unix `fcntl.flock`). A confirmed abandoned owner can be
reclaimed immediately, even before its lease or next-poll deadline; a live owner's
lock prevents takeover even after the time lease expires. The probe lock remains
held through the SQLite ownership update to avoid a check/use race. Lock files are
never unlinked, and inaccessible/missing ownership evidence is treated as unknown,
not proof of process death. Older unmarked owners retain lease-based recovery.
Actual subprocess exit/termination tests cover local reclaim below five seconds.
This is not acceptance of the broader device/model/network recovery goal.

The observer checks the persisted scheduler's enabled state before GitHub work and
before starting/publishing repairs. It respects `auto_start_tasks`, `auto_publish`,
and the scheduler's serial/parallel capacity. Proposal and repair admission share
the manager lock. Disabled evolution does not poll GitHub or launch repair Agents.
Disabling prevents new work; cancellation of an already running command retains
the existing task cancellation semantics.

Active observations poll at 30-second intervals; completed green heads are checked
again after five minutes so subsequent reruns are observable. Network/observation
errors retry after one minute. Closed PRs stop polling; merged PRs stop after
their head checks reach a known final outcome, not while evidence is pending. Each tick claims at
most four due watches; this is an observation batch size, not an Agent action budget.

The loopback-only `GET /api/evolution/v2/tasks/{task_id}/ci-watch` endpoint exposes
the durable status, exact head, checks, reserved child, and last error. Parent V2
metadata also exposes the current CI observation. No CI payload is broadcast to
phones by this observer.

## Evidence and remaining acceptance

Focused tests cover head binding, missing/unknown/partial evidence, independent
check suites, status supersession, redaction, lease fencing, simultaneous claims,
transaction rollback, actual subprocess death, 506-watch incremental recovery,
OS-held live-owner protection, immediate dead-owner recovery, unknown lock evidence,
disabled controls, task-creation interruption, restart deduplication, capacity,
and original-PR repair publication using real local Git repositories and gates.
GitHub read-only verification was performed against PR #2854's exact head.

On 2026-09-07, controlled draft [PR #2856](https://github.com/galaxyssi/GalaxySSI/pull/2856)
completed a real Provider/hosted-CI repair cycle. The observer ran from framework
commit `06e46dbdd9b5eac5a5b78394ce534056b338c7d4` in a separate process and state
directory, using a local acceptance harness. The seed commit
`bc471ea10f500d444a8100f49042694fa8810771` failed the retry-schedule acceptance
test. GalaxySSI invoked its actual Codex patch agent; the validated candidate
`f3c54084aaf9f75089f4feadb261f54d5fa738ee` was pushed by the framework to the same
PR, without a manual implementation patch or force push. All 14 reported checks
passed, including the canary and the [full backend workflow](https://github.com/galaxyssi/GalaxySSI/actions/runs/34106497170).
The observer persisted `passed` for the repaired head. The temporary PR was closed
without merging its fixture into the product. This is one controlled acceptance
run, not evidence of arbitrary-project success or a device performance percentile.

The subsequent PR integration preserves both durable campaigns and CI watches;
a regression reconstructs the manager and verifies both states without starting
workers. The combined evolution suite passes 145 tests. Subprocess tests also run
from the CI Desktop working directory instead of relying on an inherited backend
working directory.

This is not full self-evolution acceptance: device/backend restart during the live
loop, long-duration execution, and the S20U UI evidence remain to be tested. A
`passed` observation means all currently reported head checks are known green;
it is not proof of required-check configuration, branch protection, reproducible
builds, release signing, or complete evaluation coverage. The dynamic DAG campaign
adapter is included through PR #2854. [Verified campaign dependencies](evolution-campaign-verified-outcomes.md)
now connect its publication outcomes to CI/integration evidence. Full coordinator
goal acceptance, isolated candidate composition, and live cross-restart acceptance
remain outstanding.
