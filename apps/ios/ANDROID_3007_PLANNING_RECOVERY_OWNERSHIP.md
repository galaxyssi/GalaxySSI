# Planning Recovery Ownership

iOS follow-up found during the Android #3007 execution/recovery comparison,
based on main c6bad3465c673dfb2dcecb23b095185c129c7447. This covers the existing
startup initial-planning/replanning recovery callbacks, explicit user replanning,
rolling-plan continuation and selected-provider initial planning, not every planning entry
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
explicit recovery/replanning remains responsible. Local-model initial planning
planning entry points and persisted cross-profile history still need separate
review; no full recovery, privacy, storage or concurrency acceptance is claimed.

The initial eight Swift fixtures are authored, not executed: valid initial/replanning scope,
profile/cancellation/missing state, task/reference/plan drift, original source
drift, session privacy/tracking/archive/merge/preference changes, saved input
scope/privacy mismatch, matching private identity-only scope, and invalid
references. No model, native tool or network executes in these fixtures.

## Explicit User Replanning

The same PR now also fences replanLocalNativeAction with and without an existing
plan. Capture the original failed/blocked task before awaiting the journal/model.
Before a journal callback mutates state, revalidate that original owner; bind the
new pending planning snapshot after the existing upsert, validate saved input,
then gate success and error writes. The no-plan, nonjournaled model branch also
rechecks the original owner before fallback or result use.

The explicit userReplan scope is identity-only and accepts the already blocked
task and unchanged tracking-paused context used by this existing manual flow.
It does not clear blocked state or grant model/effect permissions. Automatic
startup recovery keeps planning-state admission and rejects blocked initial
planning, while preserving existing blocked replanning/readback recovery.
Four further fixture methods cover those distinctions and no-plan callback drift,
for twelve authored methods at that revision. They are not executed. Existing
upsert fault handling remains unchanged.

## Rolling Continuation

continueRollingNativePlan now binds the completed-batch waiting task before the
journal await, revalidates before changing it to pending planning, binds that
pending snapshot, checks input before the model, and gates both success and
error writes. The rolling identity scope accepts only waiting-response/planning
states with a saved plan and a non-awaiting prior result. It does not authorize
the next batch, erase uncertainty, or bypass the existing native connector wait,
browser/readback, budget, permission, outcome or continuation gates.

Like the existing live flow, blocked/readback and unchanged tracking-paused
context can remain in the rolling identity snapshot. Four new fixture methods cover waiting
identity, invalid external/live states, pending reference/tracking compatibility
and stale same-phase callbacks, for sixteen authored methods total, not run.
Local-model initial callbacks remain separate follow-up work. Already-sent
model calls, general upserts and immediate retry limitations remain unchanged.

## Recovery Compatibility

Memory tracking pause is not an execution pause. Startup recovery retains a
matching tracking-paused context, but rejects changed session or saved-input
tracking flags. Blocked initial planning remains excluded by its existing
candidate filter. Replanning retains its original readback/blocked admission;
the pending reference and saved base plan must still match exactly. No blocked
flag is cleared and no effect permission is granted by this identity check.
Two additional synthetic fixture methods cover these cases, for eighteen
authored methods total at that revision, not executed.

## Selected Provider Initial Planning

receivePhoneOwnedProviderReplyInScope now binds the original source, profile and
session before waiting for its journal. This admission scope requires the task
ID to remain absent: it cannot overwrite a concurrently inserted or existing
task. Revalidate admission before writing the first pending task, then bind the
persisted pending snapshot and validate input before sending the model request.
Recheck that snapshot before success or error writes. A journal failure before
the callback can retain the existing failure behavior only while the original
absence/source/session owner remains current.

Three more synthetic fixture methods cover absent-task admission, profile/source/
session/cancellation drift and invalid live/blocked/reference/plan states, for
twenty-one methods total, not executed. The local-model initial-planning and
later fallback inference paths remain separate follow-up work. Existing unchecked
upsert durability, sent-call and retry limitations still apply.

Only JS/source, iOS project structure and whitespace checks are included. No
Swift/native build, XCTest, simulator/device/live provider, full repository check,
CI inspection, IPA, private evidence upload or remote approval/merge is performed.
