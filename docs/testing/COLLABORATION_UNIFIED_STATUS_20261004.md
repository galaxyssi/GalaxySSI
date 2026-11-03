# Collaboration recovery and current-member state

## Scope

Android 1.4.37 (1122). Desktop code and the running Desktop process are unchanged.

The conversation list, collaboration transcript, and team detail page previously
used different kinds of state. An automatic parent recovery wait was persisted as
PAUSED and then excluded from reconciliation. Meanwhile, execution attempts were
rendered as people, queued research stages were hidden, and an INTERRUPTED
snapshot froze a still-pending member's timer.

## Changes

- Reconcile the original, identity-bound team after an audited automatic recovery
  pause. Persist WAITING_RESPONSE rather than a user pause. Do not dispatch a new
  task. Explicit user pause, stop, cancellation, and mismatched identities remain
  protected.
- Project one current execution per stable person. Prefer running work, then the
  next queued dependency, then the most recent terminal execution. Historical
  results and attempt details remain available.
- Share the projection across the conversation list, transcript, and team details.
  Restore current rows independently of the transcript's paged history window.
- Show pending member dependencies and the actual latest update time. Transport
  recovery does not freeze the elapsed waiting time or become a user pause.
- Distinguish authenticated ongoing execution, remote queue/pause, connection
  recovery, and completed-but-not-yet-delivered output. A local dispatch is not
  evidence that the remote model is running.
- Observe an open team detail page's current state from memory and refresh only
  when its projection changes, preserving scroll position.
  Database reads/writes never hold the monitor used by UI getters. Cached state
  and persisted observations are bounded; no extra model calls or MQTT polling
  are introduced.

## Verification

The focused Gradle command covers Collaboration, AgentTeam,
AgentCollaborationRuntime, AgentRemoteRecovery, ConversationHub, and
AgentLongTaskRecovery test classes, plus both debug APK builds. Native memory
compilation is excluded using the existing bundled native library.

New tests cover distinct member identity, pending dependencies, authenticated
recovery, stale attempts, preserved results, terminal failure ordering, delivery
pending, explicit pause/stop, exact parent scope, and legacy automatic-pause
reconciliation without redispatch.

The final build passed **789 tests in 63 suites**, with zero failures, errors, or
skips, including all 11 new unified-state tests and the new parent recovery test.
Both `assembleDebug` and `assembleDebugAndroidTest` passed. The Kotlin source-size
policy and staged whitespace checks also passed.

APK: `apps/android/app/build/outputs/apk/debug/app-debug.apk`.

## Device acceptance boundary

ADB did not detect S26U during this implementation. This report does not claim
installation, screenshot acceptance, or recovery of the user's original group.
The original Desktop execution was read through its diagnostic endpoint and was
completed; it was not restarted or resubmitted. Completion of that execution is
not proof that the overall research goal or any physical experiment succeeded.

When S26U is reconnected, install without clearing data and inspect the original
group's list status, pending members, timestamps, team details, and result receipt.
Do not rerun completed calculations or experiments as a display test.
