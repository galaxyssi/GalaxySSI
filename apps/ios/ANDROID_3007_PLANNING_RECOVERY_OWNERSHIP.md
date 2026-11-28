# Planning Recovery Ownership

iOS follow-up found during the Android #3007 execution/recovery comparison,
based on main c6bad3465c673dfb2dcecb23b095185c129c7447. This covers the existing
startup initial-planning/replanning recovery callbacks, not every planning entry
point or the full Android parity backlog.

Both recovery paths formerly checked only phase and pending reference after
awaiting the planner. A same-reference task edit, original message change or
profile/session change could let an old success or error overwrite current state
and potentially dispatch the old plan.

Each recovery batch now binds its profile, and each candidate binds the entire
saved planning task/reference, original user message and active session privacy,
tracking and pinned preference. Validate current readable/unlocked state and
cancellation before restoration, before invoking the model, after success and
in the error path. Profile changes stop the old candidate batch. Current source
and task changes stop the old callback without clearing its saved reference or
writing a synthetic failure into the changed task.

The restored input's conversation/turn and private/tracking flags must match the
captured current session before a model request. Matching private local planning
is not categorically blocked; existing provider/privacy checks still decide it.
A mismatched saved privacy snapshot can pause its still-current task through the
existing recovery-error path, without sending that mismatched input to a model.
Pinned preferences still use the existing current-session refresh; changes during
the await invalidate the callback instead of applying stale instructions.

## Limits

This is a current recovery-attempt fence, not a new persisted original-profile
marker in historical planning inputs. Journal hashing/leases, provider snapshots,
model selection, budgets, permissions, planning/repair, effects and general state
upsert are unchanged. It does not make existing upserts fault-checked or atomically
commit source/session/task state. Already-sent model calls are not retracted.

The full task equality is conservative, including task-log changes. Rejected or
locked/cancelled callbacks do not gain an immediate automatic retry. Existing
explicit recovery/replanning remains responsible. Other initial/rolling/manual
planning entry points and persisted cross-profile history still need separate
review; no full recovery, privacy, storage or concurrency acceptance is claimed.

Eight Swift fixtures are authored, not executed: valid initial/replanning scope,
profile/cancellation/missing state, task/reference/plan drift, original source
drift, session privacy/tracking/archive/merge/preference changes, saved input
scope/privacy mismatch, matching private identity-only scope, and invalid
references. No model, native tool or network executes in these fixtures.

Only JS/source, iOS project structure and whitespace checks are included. No
Swift/native build, XCTest, simulator/device/live provider, full repository check,
CI inspection, IPA, private evidence upload or remote approval/merge is performed.
