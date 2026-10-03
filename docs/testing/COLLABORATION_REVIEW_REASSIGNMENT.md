# Completed Review Reassignment

## Scope

Android 1.4.31 (1116) allows an incremental coordinator or goal assessment to
reassign a documentary review of the same candidate version after the host has
received a successful final response but no valid workspace publication. Previously
the same-version enrollment was ignored, even when it supplied a useful correction.

The coordinator must name the exact previous dispatch in `retry_review.node_id`,
explain the publication correction in `retry_review.reason`, and select an existing
authorized independent reviewer. The old result, candidate, original criterion,
required source contract and other work remain intact. The new task receives a
different host-owned identity and is committed with its checkpoint before dispatch.

This is not generic retry or offline takeover. Unknown, running, failed, cancelled
and skipped executions do not qualify. Nor do repairs or already published reviews.
It grants no extra tools, physical-action authority or evidence receipts. A late
publication from the old dispatch blocks the replacement at the next admission,
execution or publication check. It does not undo work already executed. Existing read-coverage and independent-acceptance gates are
unchanged. A supported review remains a member assessment, not goal certification.

## Verification

JVM coverage includes:

- Explicit replacement with a new member and unchanged target/criterion.
- Exact old dispatch, correction reason, authorized membership and independence.
- Repeated same-version attempts with distinct identities and retained history.
- Replayed requests do not duplicate work or erase a newer pending attempt.
- Late old publication blocks both planning and a previously admitted publication.
- Unknown/failed/stopped work, repair operations and existing publications fail closed.
- Pause/stop, zero admission capacity and unrelated running work retain their semantics.
- Real goal-loop and append-only runtime/store integration, checkpoint reopening and
  exactly-once replacement dispatch using local workers.

`CollaborationCandidateRuntimeDeviceTest#encryptedStoreRestoresReassignedReviewWithoutRepeatingTheOriginal`
uses dedicated encrypted databases and local workers. It does not call Codex,
DeepSeek, contacts, door tools or the user's original research.

Run the regression and compile both APKs with:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests 'com.galaxyssi.chat.Collaboration*' --tests 'com.galaxyssi.chat.Mqtt*' :app:assembleDebug :app:assembleDebugAndroidTest --console=plain
```

## Limits

No live-provider or paid-model rerun is part of this phase. Real-provider candidate
evolution, broad offline ownership fencing, long-outage/Doze/device-reboot matrices,
qualified scientific validators and equal-budget team comparisons remain separate
acceptance work. No superiority or scientific-validity claim follows from local
recovery tests.

In 1.4.31 this was not a generation-fenced ownership transfer: an old publication
could still arrive after replacement publication. The follow-up in
[1.4.32](COLLABORATION_PUBLICATION_RETIREMENT.md) closes that workspace write race
with durable publication retirement. It still cannot undo or cancel an external
side effect and is not general offline task takeover.

## Results: 2026-10-03

- Application and instrumentation APKs compiled. S26U was upgraded in place to
  **1.4.31 (1116)**; source, APK metadata and installed package agree. Data was retained.
- **773 JVM tests in 60 suites** passed, with zero failures, errors or skips
  (`Collaboration*` and `Mqtt*`). Twelve new cases cover this phase's admission,
  idempotency, late-publication, actual goal-loop and runtime/store restore paths.
- **16 local S26U regression cases passed** in a 79.024-second invocation. The
  runner listed 17 tests because it also discovered the opt-in evidence-process
  case; that one was assumption-skipped, not counted as a pass in this total.
- The evidence-process case was then explicitly run in separate seed/recover
  invocations and passed (0.039 / 0.059 seconds; PIDs 13288 / 13360).
- The separate candidate graph seed/recover pair passed (0.263 / 1.080 seconds;
  PIDs 13463 / 13644). Existing committed publication bytes were reused without
  reexecuting completed work. Each instrumentation invocation finished before the
  next one began; dedicated fixture contents were cleaned by their recovery tests.
- The new same-version reassignment test exercises encrypted-store reopening in
  one process. The separate-process pair exercises the existing multi-candidate
  graph/publication path; it is not reported as a cross-process reassignment test.
- An initial build exposed a fixture-only checkpoint/record type mismatch. The
  fixture was corrected, and the full final regression/build passed without
  relaxing production guards. The 153,600-byte Kotlin size policy and
  `git diff --check` passed. Repository-wide checks were not rerun.
- Desktop was not modified or restarted. No paid model, original research, contact
  messaging or physical tool was invoked. S26U was returned to GalaxySSI afterward.
