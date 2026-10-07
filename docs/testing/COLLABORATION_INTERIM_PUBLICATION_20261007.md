# Interim Collaboration Publication

Android 1.4.85 / 1170 and Desktop 1.4.24.

## Scope

A member can publish useful versioned workspace artifacts while its assignment
is still running. The `collaboration_publish` capability is exposed to bound
Android streaming cloud conversations and the Desktop Codex dynamic-tool
adapter. It is distinct from the read-only `collaboration_recall` capability.

This increment does not wake the scheduler on a milestone, start a peer before
its existing dependencies complete, change model selection, or introduce a new
research loop. Milestone-driven scheduling is separate follow-up work. Other
remote providers and the local native phone-tool catalog are not wired to this
new capability in this increment.

## Contract

- `mode=publish` takes a stable `milestone_id` and a research-artifact JSON
  string containing at least one versioned workspace object.
- The host binds group, run, turn, member, node, and execution generation;
  the model cannot select those authority fields.
- Workspace revisions and the publication receipt commit atomically. Accepted
  IDs are immutable; an identical retry returns the existing receipt without
  another version or side effect. Failed drafts remain available in the journal
  and may be corrected under the same ID until accepted.
- `mode=list` recovers the assignment's saved IDs using opaque pagination.
  Thirty-two items is a page size, not a total publication or task limit.
- A final research artifact may include `milestones:[saved IDs]`. The host
  resolves exact originals from that assignment rather than recreating objects
  or adopting another member's authorship.
- Interim publication is neither assignment completion nor scientific
  verification. Existing candidate-transition and independent-review contracts
  are retained. Specialized host candidate transitions still publish finally.
- Paused, retired, revoked, or mismatched assignments cannot publish. Replies
  are rechecked after storage access to avoid returning newly revoked data.
- Remote requests and replies are transient MQTT RPCs, not durable outbox
  records. A lost response instructs the caller to retry the same ID and payload
  or list saved IDs; it never requests repetition of an external effect.
- The Android cloud loop refreshes publication/list results instead of freezing
  them in the web-search cache. Publication-only rounds do not consume search
  call counts, become search evidence, or trigger the no-search-progress
  synthesis path. Existing research time and cancellation policies remain.
- A request has an explicit 128 KiB UTF-8 envelope. Oversized requests receive a
  split-delivery error, not truncated evidence. Journal records and failed
  drafts share the group's existing deletion namespace.

## Verification

Verified locally on 2026-10-07:

- 1,328 Android collaboration/cloud unit tests passed with no failures or skips.
- Debug and instrumentation APK builds passed.
- 212 Python tests and 123 subtests passed, including MQTT query policy,
  authenticated dispatch, recovery and task-turn routing.
- 68 Desktop JavaScript tests and repository structure checks passed.
- Seven instrumentation tests passed on the authorized SM-S9480: three interim
  publication tests and four existing numeric-feedback regression tests.
  Android 1.4.85 / 1170 was installed without clearing application data.
- The initial device run had one fixture failure because removal of the author
  left that member as coordinator. The fixture now assigns the remaining peer
  as coordinator before revocation; the corrected complete run passed.

Desktop source is updated to 1.4.24. Replacement of the previously running
1.4.23 instance is pending manual exit; these tests do not claim live deployment
of the new remote publication callback.

The focused Python suite exercises both the broker and Codex dynamic-tool
callback with authenticated mock replies. It covers route, turn, generation,
phase and contract mismatch; cancellation; uncertain delivery; same-nonce
retransmission; immutable IDs; and publication not being reported as a web
search or completed worker.

The Android tests cover immutable revisions, atomic storage failure, repairable
failed drafts, cursor isolation, exact final references, corruption detection,
group cleanup, provider schema parity, and read-only publication repair.
Instrumentation uses dedicated synthetic groups and real encrypted phone
storage. Reopening a store is not a full process-death or device-reboot test.

No real-model call is required by these tests. They do not establish autonomous
method revision, causal peer improvement, skill retention, generalization, or
an end-to-end live MQTT publication. Private manuscripts, experimental traces,
and runtime state are excluded from this change.

## Reproduction

From `apps/desktop/core/galaxyssi-link/backend`:

```powershell
python -B -m pytest -q test_collaboration_milestone_bridge.py test_collaboration_numeric_recall.py test_collaboration_recall_bridge.py test_collaboration_recall_retry.py test_codex_tool_evidence.py test_agent_tool_evidence.py test_codex_conversation_threads.py test_codex_experiment_boundary.py test_codex_startup_concurrency.py test_mqtt_query_delivery.py test_signal_receive_dispatch.py test_mqtt_agent_recovery.py test_mqtt_task_turn_routing.py
```

From `apps/android`, with the Android SDK configured:

```powershell
.\gradlew.bat :app:testDebugUnitTest --tests '*Collaboration*Test' --tests '*Cloud*Test' -x :app:buildNativeMemory --console=plain
.\gradlew.bat :app:assembleDebug :app:assembleDebugAndroidTest -x :app:buildNativeMemory --console=plain
```

The native-memory exclusion reuses an existing native artifact; it is not a
fresh verification of the Rust build. With both matching APKs installed:

```powershell
adb -s <authorized-device> shell am instrument -w -r -e class com.galaxyssi.chat.CollaborationMilestoneDeviceTest,com.galaxyssi.chat.CollaborationNumericFeedbackDeviceTest com.galaxyssi.chat.test/androidx.test.runner.AndroidJUnitRunner
```
