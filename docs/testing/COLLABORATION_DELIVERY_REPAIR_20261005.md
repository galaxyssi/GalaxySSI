# Collaboration Delivery and Repair - 2026-10-05

## Observed Failure

A continuing research goal repeatedly requested two work IDs that were already in
the ended-execution ledger. The dependency compiler silently removed both IDs,
leaving only the coordinator assessment. One earlier successful late response had
been applied directly to the execution record without the normal archive and
workspace-publication path. A successful dispatch therefore did not imply that its
deliverable was available for a subsequent independent check.

The diagnosis does not establish completed protein design, folding prediction or
physical validation. Recorded sequence/structure counts and model-written reviews
are not substitutes for validated computations or laboratory evidence.

## Changes

- New ordinary goal assignments cannot silently reuse ended IDs. The coordinator
  receives the exact IDs and instructions to use a distinct repair ID, `repair_of`
  and a concrete reason. Existing checkpoint graphs and host-validated workflow
  replays still skip finished steps without redispatching their effects.
- Live and recovered replies use the same finalizer: archive the complete original,
  validate/publish versioned workspace data, attach a host delivery receipt, then
  persist execution completion. Replaying the reply cannot duplicate publication.
- Delivery status is independent of execution status and scientific acceptance.
  Rejected or empty deliveries retain an actionable diagnosis; long handoff
  projections no longer claim that rejected workspace changes were committed.
- Late responses match original run, conversation and stable member-dispatch
  identities. Storage errors leave the response pending, without asking a model to
  repair a storage failure. Each failed reconciliation is isolated from other runs.
- Existing complete, untruncated historical late research artifacts can be
  backfilled into the archive/workspace. Recovery reads two historical checkpoints
  per pass, persists its cursor, and never rewrites execution history or invokes
  providers/tools. Truncated, candidate-specific, mis-scoped and unverifiable
  records are not silently promoted. Paused/stopped teams are not backfilled.
- The team header says `Awaiting a revised plan` when no member is executing or
  waiting and the goal is still continuing. An empty continuation also receives
  `NO_EXECUTABLE_WORK` feedback rather than appearing to advance research.

## Verification

Android version: **1.4.52 (1137)**. Desktop is unchanged.

Deterministic coverage includes complete late-reply archival, receipt persistence,
idempotent publication, rejection diagnostics, write failure, identity isolation,
historical backfill without event mutation, empty delivery rejection, truthful
long-output projection, new repair dispatch and unchanged original-work call count.
Existing collaboration, live-graph, workflow, candidate, acceptance and subagent
regression tests are run alongside the new tests.

Reproduction from `apps/android` with the existing SDK/Rust environment:

```powershell
./gradlew.bat :app:testDebugUnitTest `
  --tests '*Collaboration*' --tests '*AgentTeam*' --tests '*AgentSubagent*' `
  :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
```

`CollaborationResultFinalizerDeviceTest` uses a dedicated synthetic group and
encrypted store. It reopens persisted receipts and full originals, checks duplicate
replay, and removes only its own fixture. It does not launch an activity, call a
provider or resume the user's research.

Frozen-source verification passed **989 tests across 75 suites**, with zero failures,
errors or skipped tests. Main and instrumentation APK assembly passed in **7m 27s**
(106 tasks, 15 executed). Kotlin source-size policy (153600-byte default) and staged
whitespace checks passed. Existing deprecation warnings remain unrelated to this fix.

Main APK SHA-256:
`59cec7d6483127fc02180a14ce896e5b24518a5dda6bc9c000f99f107c267866`.

This revision has **not been installed or device-tested**. The instrumentation test
is compiled, not counted as a passing device test. No original research was resumed,
and no real model/provider call, Desktop restart or other-device operation was made.

## Remaining Acceptance

No real model call, protein computation, laboratory experiment or automatic restart
of the original research is authorized by these fixtures. The original group's
end-to-end recovery, independent scientific acceptance, and long network/Doze/reboot
campaigns still need separate observation. These changes fix delivery and planning
feedback, not unavailable domain validators or laboratory resources.
