# Parallel Native Dispatch Ownership

Independent iOS follow-up to the Android #3007 execution checkpoint audit, based
on main c6bad3465c673dfb2dcecb23b095185c129c7447. This is not the entire execution
loop/audit-batching port or a complete Android parity claim.

## Actual Dispatcher Changes

The parallel dispatcher formerly ignored task-save failure before launching its
detached work. On return it only checked the task ID and executing phase, then
wrote its captured old task. A revised or replaced still-executing task could be
overwritten. Result UI handoffs and message progress preceded final task save.

The dispatcher now admits only the exact still-current plan. A local ownership
snapshot validates the profile, process, original user source, exact native
members and running checkpointed plan. A checked task commit succeeds before
the detached executor or node claim can start. The existing per-node encrypted
claim still saves final prepared input/checkpoint/intent before each effect.

After suspension, the same profile, full task snapshot and stable source fields
must still match, and cancellation must remain absent. Each of the four result
branches performs another checked compare-and-commit before emitting progress,
opening a handoff, publishing a reply, scheduling review or continuing actions.
The new Store entry point preserves outcome-completion guarding, then commits
the task before the existing workspace projection and best-effort self-model
observation. General upsert and the underlying task-commit kernel are unchanged.

## Deliberate Limits

The full task comparison is conservative: even an independent task-log update
rejects this old projection. Already committed per-node observations are not
deleted or turned into synthetic failures; no tool is repeated by this check.
Existing interruption recovery remains responsible for those observations.
This does not promise immediate projection retry for every same-process race,
atomic task/workspace/node/self-model storage, cross-process CAS, guaranteed
power-loss durability or exactly-once external effects. Started work is not
remotely cancelled merely because result projection loses ownership.

Source stable fields include message/peer/conversation/turn, user/system flags,
text, rich attachments, voice transcript, analysis mode and source conversation.
Delivery status/traces are not new authorization. No permission, consent, route,
budget, provider or journal-execution policy is added or bypassed.

## Verification

Eight Swift fixtures are authored, not executed: exact scope, foreign profile and
cancellation, task/plan/process drift, source drift, invalid/duplicate members,
checked Store reopen, stale/cancelled commits and injected state-write rollback
before a synthetic execution counter. Source contracts pin actual dispatcher
ordering and retain the native executor/claim/observation and general Store paths.

Only JS/source, iOS project structure and whitespace checks are permitted. No
Swift/native compilation, XCTest, device/simulator/live provider, full repository
check, CI inspection, IPA or remote approval/merge is performed.
