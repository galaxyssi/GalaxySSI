# Live Receive And Recovery Queue Admission

## Scope

This checkpoint belongs to draft PR #3045. It does not complete the Android +
Desktop acceptance specification. The user's stop boundary is this PR; no new
features outside its scope are added. Remaining release gates stay explicit in
[implementation progress](../engineering/MQTT_MULTIPATH_PROGRESS.md).

The fixture uses two isolated Desktop/native Signal workers and three owned
loopback TLS brokers. Each run includes 30 idle cancellations, 30 cancellations
overlapping attachment traffic, and one excluded warm-up. It checks authenticated
business dispatch and persisted cancellation state, not a live model process.
The 32 MiB attachment has 128 application chunks of 256 KiB. Its phone-shaped
payloads enter Desktop's MESSAGE sender policy, not Android's P2 CHUNK striping.
No phone, public broker load test or production Desktop instance was operated.

## Finding

`build/mqtt-native-control-ingress-profile-v1/report.json` passed its business
checks and the existing provisional 8000ms loaded cancel-result p95 budget.
There was no production optimization between the preceding lock-fix checkpoint
and this profiling run. Loaded cancel-result p50/p95 was 3684.9669/7325.1864ms;
idle was 2290.3484/4548.5183ms. Timing variation alone is not a speedup claim.

Per-call receive observations exposed a separate race: 11 of 30 loaded request
handlers and six of 30 return handlers ran through stored recovery despite a
valid first live receive. `pending()` assigned a recovery admission token and
five-second queue-spacing deadline while the live receive was handing off its
newly stored message. `begin()` treated that queue reservation as a reason to
defer the live handler. The actual OS dispatch guard was not owned by recovery.

The probes retain bounded records for each receive invocation, with its message
identity and associated ACK invocation. Same-endpoint clocks give these loaded
baseline stage measurements (milliseconds, nearest-rank percentiles):

| Stage | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Request callback to receive-handler start | 1605.7059 | 2657.1166 | 2777.4899 |
| Request Signal decrypt/handoff journal span | 85.9442 | 140.8608 | 763.5364 |
| Request first live delivery entry to actual business dispatch | 255.1654 | 2357.4763 | 2992.8433 |
| Return callback to receive-handler start | 63.3318 | 915.2201 | 2849.4131 |
| Return Signal decrypt/handoff journal span | 83.4405 | 434.6436 | 690.8237 |
| Return first live delivery entry to event capture | 217.6141 | 2198.8507 | 3441.8921 |

Decrypt/handoff spans include persistence work, not only cryptography. The
first-live-entry to business marker deliberately follows the same immutable
message across invocations if recovery performed the work. This is not an ACK
duration. Percentiles are not additive; clocks are not subtracted across workers.

## Fix And Safety

Only a never-executed `stored` message with an outstanding recovery admission
may run immediately through a live delivery holding its OS guard. Durable body
comparison, authenticated ingress and dispatch ownership remain unchanged.
Finishing that handler makes the queued recovery invocation observe `dispatched`
instead of performing the operation again.

The exception does not bypass failed-handler retry backoff, stale nonempty
admission tokens, an active OS lock or interrupted unsafe external effects.
The regression `test_recovery_queue_cannot_delay_live_first_delivery` failed
before the production change (`deferred` instead of `run`) and passes after it.
Separate tests preserve retry admission and unsafe-interruption behavior.

The load harness now requires one live dispatch and one live return capture for
each uninterrupted measured task, with zero dropped probe records. Intentional
crash/recovery scenarios remain separate and do not use this live-only gate.
The pre-fix profiling report predates that gate; its exit 0 must not be called a
pass of the new receive-flow assertion.

## Verification

- 242 focused/expanded backend unit tests passed, including dispatch, native
  handoff, compaction, pool, delivery, receipt retry and chunk receipt coverage.
- 41 lab unit cases passed in their appropriate environments: 29 endpoint cases
  and 12 controller cases. The endpoint runtime has Pillow/native dependencies;
  the controller has the owned TLS broker dependencies.
- Desktop's 37 checks and structure check passed.

| Owned native run | Idle cancel p50 / p95 ms | Loaded cancel p50 / p95 ms | Loaded provisional gate |
| --- | ---: | ---: | --- |
| Pre-fix ingress profile | 2290.3484 / 4548.5183 | 3684.9669 / 7325.1864 | Pass; old business/performance gate only |
| Admission fix v1 | 2124.8927 / 2764.9319 | 3256.1883 / 4905.6367 | Pass |
| Admission fix v2, isolated repeat | 2010.3076 / 2882.4299 | 4260.7061 / 6291.2312 | Pass |

Admission fix v1 passed 61 cancellations, all 30 overlap checks and the complete
artifact with one available result. Both directions in both measured cohorts
had 30 live / zero recovered / zero ambiguous / zero dropped receive records.
Controller attachment completion took 196.781s; shutdown was normal and cleanup
errors were empty. A Desktop structure check finished shortly after this run
started, so v1 is not an isolated performance comparison.

The isolated v2 repeat passed the same 61 cancellations, all 30 overlap checks,
one complete artifact, and the four 30-live receive-flow assertions with zero
recovered/ambiguous/dropped records. Controller attachment completion was
269.703s. Exit was 0 with empty cleanup errors. No build or other test suite ran
alongside its latency sampling. Both runs pass the unchanged provisional budget,
but their variation and fixed idle-before-loaded order do not prove a stable
Internet/phone p95 or a particular causal percentage speedup.

Original and reconstructed file SHA-256 for the successful 32 MiB runs:
`c539e9b0e61d579fab6bdb87ab460ca11cc9704ccef711e2fa8c15d9dc123dcc`.
Each cohort submitted 90 control frames, 30 per path, totaling 1,974,060 counted
MQTT bytes including 1,316,040 redundant bytes. This excludes attachments,
receipts and IP/TLS overhead; it is not total network traffic.

The post-change owned native recovery regression also passed: 20 business
messages and three path cycles, including process death, all-path restoration,
held resume/receive receipts and subscription withdrawal after selection.
`build/mqtt-native-admission-recovery-v1/report.json` reports `passed`; the process
exited 0 and both endpoint logs were empty. This checks that the admission change
retains real native receive and delivery recovery, not phone lifecycle behavior.

Earlier failed control/load runs remain recorded in the
[previous report](MQTT_CONTROL_ATTACHMENT_20260913.md). These results do not
establish Android, public-network, real-provider or full release acceptance.

## Reproduction

From the PR worktree, with the documented Java 21 runtime:

```powershell
& $controllerPython tools/testing/mqtt_owned_lab/native_control_latency.py `
  --endpoint-python $endpointPython `
  --report-dir build/mqtt-native-control-admission-fix-v2
```

Keep builds and other test suites idle during latency samples. Reports and logs
are retained in ignored `build/` directories; the checked-in document records
their scope and results, not generated private runtime state.
