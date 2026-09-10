# Android Action Effect Journal

Android 1.1.52 (938). Desktop and iOS are unchanged.

## Entry Points

MainActivity's direct non-native system-action dispatch now enters
`MobileNativeAgent.executeAction`, using its original executor and captured
screen. Ordinary mobile legacy actions, observation-triggered recovery attempts
and rollback actions use the same action-effect adapter. Existing native-tool
calls keep their own registry journal; the adapter does not recursively wrap
them. Pure `READ_SCREEN` calls remain fresh and do not initialize the journal.

The plan-node journal remains responsible for plan-node observations and
verification. The action-effect journal covers the actual dispatch beneath it,
including entry points that do not have a plan node. These are separate child
Run identities in the existing encrypted Run Kernel, not separate persistence
engines.

## Identity and Recovery

The action key binds client route, session, conversation, goal, task, turn and
action ID. One dispatch namespace allows changed action kinds with the same
identity to be rejected as input conflicts. The input digest binds kind, target,
description, parameters, risk and confirmation intent. Presentation status,
previous result text and the newly observed screen are not execution identity.

An owned connector fallback trail creates a child attempt key from the selected
resource and persisted attempted/retried resource sets. This lets Auto move to
another Provider, or perform its existing deferred return, without changing the
parent action ID. Restoring the same attempt replays its receipt. The child key
does not hash arbitrary action inputs: changing a prompt within that attempt
still causes a conflict. Stale trails, non-connector actions and manually locked
targets cannot create fallback child keys.

Before calling the original executor, the adapter reads an existing claim or
atomically acquires one. A completed receipt returns the original action ID,
success, message and full metadata. In particular, connector `awaiting_response`,
request IDs, Run IDs and artifact metadata are not replaced by a generic success.
An unfinished claim returns `effect_outcome_unknown` without redispatching.
Different input under the same action identity is rejected before execution.

Results, including failures, commit before returning to the caller. A failed
commit leaves the claim uncertain rather than publishing success. Exceptions
from the original executor are recorded as failures; they are not proof that an
external effect did not happen. The model can inspect state and propose a new
repair action with a new identity. This does not add approvals or keyword-based
execution policies.

The native `AgentActionNativeToolExecutor` also preserves a result that its
delegate has already returned. A late cancellation must not turn an already
completed platform action into a cancelled receipt. The initial cancellation
checkpoint remains in place.

## Concurrency and Boundaries

The adapter reuses `AgentNativeToolReplayStore` and its encrypted implementation
without adding the native-tool admission gate, a global write lock, a new hard
timeout, polling, model calls or an additional routing layer. Existing delegate
admission and cancellation policies remain authoritative. Concurrent claims for
one identity have one owner; independent actions are not serialized here.

Receipt durability is not arbitrary external-system exactly-once execution.
Connector acceptance remains acceptance, not proof of a final model reply.
Endpoint reconciliation, replies arriving during recovery, and actions that
bypass both the mobile entry point and native registry still need their own
integration and full acceptance. Old unjournaled operations cannot acquire
historical receipts retroactively.

## Verification Coverage

JVM coverage includes original metadata, stale UI state, independent execution
scopes, input/kind conflicts, unreadable journals, failed commits, failure replay,
deliberate repair actions, fresh reads, concurrent duplicate suppression,
independent-action concurrency and cancellation after native platform success.
It also covers provider switches, deferred returns, restored fallback receipts,
changed fallback inputs, stale trails and incomplete fallback commits.

Device tests exercise the actual `MobileNativeAgent` direct entry and an Android
platform launch of GalaxySSI itself, reconstructed runtimes and encrypted SQLite,
connector-acceptance metadata with a controlled delegate, and replayed rollback.
The explicit crash phases kill the test process after the real platform launch
and before receipt commit, then verify the same case without another dispatch.
Those phases retain their test-owned database, dispatch counter and evidence.
They are not a real cloud-provider fault test.

## Initial Verification (2026-09-10)

- Based on fetched main `82ec3688e` (PR #2978). Android 1.1.51 (937) built
  successfully with the debug instrumentation APK in 9m09s. Full JVM run:
  3,498 tests in 504 suites, zero failures/errors, five skips.
- Repository checks, 73-library 16 KiB alignment and 24-library QNN packaging
  passed. No ASR/QNN implementation or model settings changed.
- SM-T575 was upgraded in place. First installation remained 2026-09-07
  07:17:23; last update became 2026-09-10 14:39:27. Preflight available memory
  was 1,770,956 KiB, data storage had 41 GB free, and the database directory
  occupied 89,764 KiB. No user messages, pairing or models were cleared.
- The installed 1.1.50 fallback baseline passed all 12 tests in 9.195 s.
  On 1.1.51, the combined action-journal and fallback suite passed 16 actual
  tests in 19.997 s, with two explicit crash/recovery phases skipped. The suites
  differ in scope, so these durations are not a latency comparison.
- Crash case `20260910-v1151` executed an actual Android launch of GalaxySSI,
  then killed process 17612 before committing its receipt. New-process recovery
  passed in 0.296 s, returning `effect_outcome_unknown` without redispatch.
- The same retained case passed again in 0.335 s after a physical device reboot,
  without reseeding. Boot ID changed from
  `748770b9-f8f2-413a-90db-54980d1636f6` to
  `828e2950-97c6-4712-b760-3eb049eb0459`. The dispatch count remained one.

APK SHA-256:
`ED43FFAEED2E9C66A8AAF6F7C78A3E2AEC4AD2365677D1E2C6C63664F444F0CD`.
Local logs: `build/action-effect-final-build.log`,
`build/action-effect-fallback-before.log`, `build/action-effect-device.log`,
`build/action-effect-crash.log`, `build/action-effect-recover.log` and
`build/action-effect-reboot.log`.
This verifies selected production entry points and durable recovery, not every
external service or a complete multi-day Agent goal.

The broader 48-item device regression then exposed an existing main-branch
rolling-batch recovery failure: an inherited `PAUSED` phase was mistaken for a
new pause after the planner was called. One assertion failed in 211.025 s;
this run is not accepted as a passing regression. Version 1.1.52 explicitly
enters `PLANNING` at admitted node recovery, retains completed output and still
honors pause/cancel requests made during assessment. Already cancelled recovery
does not call the model. New regression coverage preserves these boundaries.

## Release Verification (1.1.52)

- Full build passed in 7m06s. JVM: 3,498 tests, zero failures/errors, five skips.
  Repository and both native packaging gates passed again on the final APK.
- SM-T575 in-place update: version 1.1.52 (938), last update 2026-09-10
  14:55:12, unchanged original first-install timestamp.
- The previously failed recovery assertion and two new pause/cancel cases
  passed (three actual tests, no skips) in 0.488 s.
- The full seven-class device regression passed in 157.116 s: 56 actual passes,
  12 opt-in lifecycle skips, zero failures (68 runner entries). It includes the
  direct-action journal, Auto fallback, native mutations, observation recovery,
  ordinary plan nodes, encrypted receipt retention and task model snapshots.
- The original crash case `20260910-v1151`, retained across the app update,
  passed again in 0.312 s without a second dispatch or fixture reseeding.
- After another physical reboot, that same case passed in 0.519 s. Boot ID
  changed from `828e2950-97c6-4712-b760-3eb049eb0459` to
  `efeac09c-38a4-4a75-9858-e836a08923df`. The original claim and count remained.
  Final force-stop/Activity launch returned `Status: ok`, `WaitTime: 4806 ms`.
  This single launch sample is not a startup or content-readiness percentile gate.
- Read-only provider preflight still found no ready direct cloud Provider.
  Paired Desktop reasoning inventory passed, but that proves only local pairing
  records, not broker connectivity or a completed real model request.

Release APK SHA-256:
`686AC737DED21084D9448C1BE0686A50AB182A73A5A62B97FC48E24124B45521`.
Final logs: `build/action-effect-v1152-build.log`,
`build/action-effect-paused-recovery-fixed.log`, `build/action-effect-v1152-device.log`,
`build/action-effect-v1152-upgrade-recover.log`, `build/action-effect-v1152-16kb.log`,
`build/action-effect-v1152-qnn.log` and `build/action-effect-v1152-repo.log`.
