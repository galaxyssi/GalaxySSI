# Separate broker capacity from application receipts

## Scope and cause

Desktop 1.1.41; Android remains 1.1.41 (927). This change builds on the
physical publish bounds in PR #2961 and the recovery fixes through PR #2966.

Real case `live-final-1788977107581` completed one Codex execution, but its
process-death recovery exceeded the unchanged 60-second body deadline. Before
deployment, read-only SQLite inspection still found eight priority-95 records
from that interval queued with zero publish attempts. No queue was cleared.

The scheduler counted broker-acknowledged rows awaiting application receipts
against physical send capacity until their exponential retry deadline. Older
same-priority retries also preceded fresh control responses. Enqueue completion
was therefore not evidence that a response had reached MQTT or the device.

## Implementation

- Release physical capacity after PUBACK, while retaining durable rows until
  authenticated peer receipt or the existing retry-exhaustion policy.
- Track reservations before calling external publish code. Retain priority
  metadata until PUBACK, even when an early peer receipt already deleted the row.
- Release reservations on claim, pairing lookup, network, and batch exceptions.
- Prefer unattempted messages over retries of equal priority. Retain ciphertext
  and retry backoff; no task is resubmitted or marked delivered on PUBACK alone.
- Preserve normal global 4 + 1 reserve, per-route 2 + 1 reserve, and the separate
  artifact lane (global 2, per-route 1). Network I/O remains outside queue locks.

This is bounded physical dispatch, not a lifetime action budget. Infinite fresh
traffic fairness is not proven by the finite-backlog regression suite.

## Automated verification

- Four original regressions failed before the fix.
- 83 capacity, delivery, batching, callback-registration, route, and priority tests
  passed after the fix, including four additional failure/priority cases and
  two actual callback-registration metadata cases.
- 57 artifact-lane, recovery-query, inline-page, tracing, and peer-receipt tests
  passed. Total: 140 backend tests.
- Desktop check: 29 tests and structure check passed. Repository guard passed.
- The 10,000-row queue probe selected eight records in 31 ms; this is one local
  scheduling sample, not a network latency or percentile claim.

Evidence: `build/broker-ack-capacity-{before,tests}.log`,
`build/broker-ack-recovery-tests.log`, `build/broker-ack-desktop-check.log`, and
`build/broker-ack-repo-check.log`.

## Real SM-T575 verification

Only `R52R90282TY` / SM-T575 was attached. Desktop was gracefully restarted after
both task pools and the runtime reported idle. Existing encrypted queue, pairing,
keys, models, and user conversations were preserved. No APK reinstall was needed.

Original case `live-final-1788977107581` resumed without another setup or model
submission. The same final body hash recovered in 24,117 ms (connection 2,304 ms,
body after readiness 21,813 ms). All eight previously unattempted records had
subsequently been published. UI first-visible was 19,131 ms; Activity recreation
retained the correct conversation and exactly one assistant entry. A later plain
cold launch displayed that one entry in 2,581 ms. Desktop still reported attempt
1 and execution generation 1 for the original completed task.

Fresh case `live-final-1788978937857` passed all four phases: actual Chinese Codex
request, deliberate final-drop, headless process-death recovery, UI recreation,
and another plain cold launch. Recovery took 6,119 ms (connection 2,487 ms, body
after readiness 3,632 ms); first-visible took 12,030 ms, and subsequent cold
visibility 2,541 ms. Both UI assertions found exactly one assistant entry.
Desktop reported completed, attempt 1, generation 1, in conversation
`42d240d0-3017-49e6-a544-ca097a9868c6`.

Evidence: `build/live-final-1788977107581/` (including the preserved
`inbox-before-queue-fix.log` and pre/post queue metadata),
`build/broker-ack-live-1788978937857.log`, and
`build/live-final-1788978937857/`.

The timing reporter could not produce complete cross-device stage coverage for
the resumed original case after the backend restart; it failed explicitly rather
than substituting zero. It passed for the fresh case. Phase measurements above
are device monotonic measurements, not subtraction of phone/Desktop wall clocks.

## Not accepted yet

Recovery still exceeds five seconds, and first UI presentation remains slow.
Original UI dispatch samples included 2,977 ms and 8,111 ms consume intervals;
the next investigation must separate their remaining store/runtime dependencies.
These two real cases do not establish P95/P99, device-reboot coordination, full
Provider chaos, all runtime paths, or the broader unified-kernel acceptance goal.
