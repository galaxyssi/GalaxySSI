# Desktop Codex Startup Contention

## Scope

Follow-up to PR #2900. The previous ten-window live run completed five model tasks; four other requests reported `thread/start` timeout and one reported `turn/start` timeout. This change does not raise request timeouts, reduce the test workload, remove encryption, or replace real model results with fixtures.

Desktop source version: 1.1.6. Android application remains 1.1.4 (890); only the opt-in test APK gains an aborted-fixture cleanup command.

## Blocking Paths

- `start_task()` reserved a conversation and held the global state lock across thread creation/resume RPC waits. Notification handlers and other tasks also need that lock.
- The stdout reader handled notifications synchronously, including checkpoints, external callbacks and dynamic tools. A blocked notification prevented later JSON-RPC replies from being read even when the child process had already written them.
- Combining these paths can stall startup; simply extending the 30-second timeout would preserve the blocking dependency.
- A failed pipe write also left a pending RPC waiter registered.

## Implementation

- Atomically reserve the run/conversation under the state lock, release it before thread lifecycle RPC work. A simultaneous request for the same conversation still receives the existing busy response.
- Serialize process initialization with a separate lifecycle lock, also used by close. Initialization no longer holds the shared task-state lock while waiting for its response.
- Read JSON-RPC results directly on stdout and dispatch notifications in order on a separate worker. Each process has one bounded queue (4096 notifications), not one thread per notification. The worker exits after reader completion or process replacement.
- Keep backpressure when the queue fills, rather than silently dropping final outcomes. This is not a complete high-scale scheduler: sustained slow notification processing can still fill that queue and needs a future per-run scheduling/overload policy.
- Remove pending RPC entries on success, timeout and write failure. Keep pipe writes serialized separately.

## Deterministic Verification

Five new tests cover ten replies arriving behind a blocked notification, ordered notification delivery, startup lock availability with same-conversation exclusion, resume lock availability, handler error recovery and failed-write cleanup.

Running these five tests against the original committed implementation produced three assertion failures and one timeout error. The fixed implementation passes all five. Existing isolation/session tests also pass: 68 tests in the combined suite, plus 32 MQTT routing/intervention tests, 100 total.

## Deployment and Live Test Notes

- Replaced the idle running Desktop with this worktree's implementation. The existing desktop identity, paired contacts and Signal store were retained.
- The first launch lacked an explicit path to the installed Signal sidecar. That preparatory run never reached model execution and was aborted; it is not a valid model-performance sample.
- Subsequent admission attempts exposed stale Android global run-slot leases left by the aborted requests. The test helper only cancels the exact ten conversations named in the saved aborted report, validates their test-only transcript markers, and releases leases matched to their pending/terminal identities. It does not clear unrelated tasks, change the capacity limit, or delete transcripts.
- Android failed-delivery lease cleanup remains a separate production issue; this test-only cleanup must not be represented as its product fix.

Local diagnostic artifacts remain under `build/codex-startup-*`; earlier failures are retained separately from the final clean run.

## Final Real-Model Result

Run `stress-c80b5569-8f9e-44e9-90fe-9efe55ffbb59`, SM-T575, the unchanged 80-row arithmetic/unique-marker task, real paired Codex Agent:

| Measurement | Result |
| --- | --- |
| Desktop model task completion | 10/10 |
| Correct result rows | 800/800, all ten unique markers match |
| thread/start or turn/start timeout | 0 |
| Submit-path confirmation interval | 1571-3830 ms, from codex_turn_submit_started to codex_turn_submitted |
| Overlap of confirmed submitted turns | Peak 10 (provider submission-to-completion intervals, not proof of ten simultaneous hardware inference slots) |
| Correct final answers received by Android test | 9/10 |
| Strict Android window test | FAILED: reply 9 rendered timeout, 381.49 seconds |

The ninth model task completed correctly on Desktop, but its request was already marked message-not-delivered on Android before the delayed remote outcome. This is distinct from the previous receipt-proof fix, which protects replies already durably received. The strict test was not weakened: its expected answer marker and ten-running observation assertions remain unchanged. The phone observed at most seven concurrent running status updates; transport observations can lag actual provider execution.

Thus the reproduced model-startup timeout is fixed in this sample; the complete phone-to-Desktop-to-phone success rate is NOT 100%. A follow-up must address premature terminal transport failures, stalled inbound/outbound delivery and failure-path slot release. No replies were fabricated to repair that missing result.

Evidence: `build/codex-startup-desktop-results.json`, `build/codex-startup-live-final-report.json`, `build/codex-startup-live-final-device.log`. An additional final-review guard keeps new thread binding inside the lifecycle lock to prevent an eviction gap; it is covered by the regression suite, not a second ten-model run.
