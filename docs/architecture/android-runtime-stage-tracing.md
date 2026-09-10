# Android Runtime Stage Tracing

Android 1.1.53 (939) extends the local agent-latency contract through the actual
mobile action and verification entry points. Desktop and iOS are unchanged.

## Measured Boundaries

| Metric | Boundary |
| --- | --- |
| `phone_runtime_action_dispatch_ms` | Existing action dispatch, including native admission or durable receipt lookup, through its returned result |
| `phone_runtime_screen_observe_ms` | Post-action observation when the action may change the screen |
| `phone_runtime_receipt_observe_ms` | Receipt-only observation when no screen capture is required |
| `phone_runtime_result_verify_ms` | Applying the observed outcome to the existing action result |

These are not provider TTFT, physical screen scan-out, or pure executor timings.
Replayed receipts still measure a dispatch invocation, but do not imply another
external effect. A connector accepted for asynchronous execution counts as a
completed dispatch, not a completed model response. Screen timeouts and failed
actions are excluded from success percentiles; known cancellations retain their
own outcome. Empty observations are not manufactured as successful verification.

The recorder creates an independent opaque operation ID per invocation, allowing
concurrent actions, retries and nested calls within one task to remain separate
samples. It uses the existing transport task parameter when present, otherwise
the explicit/current turn, plan or session identity. IDs are hashed, and no
prompt, arguments, returned text, screen content, paths or credentials are added
to the diagnostic point. Existing task authorization is unchanged.

All production boundaries use Android's local monotonic clock and the existing
asynchronous, bounded diagnostic journal. No extra thread, network message,
global execution lock, sleep, timeout or durable side-effect write is added.
Writer, clock and classifier failures cannot retry an action, replace its
returned value or swallow its original exception. A disabled recorder executes
the original block directly.

The existing performance dashboard displays all four stages with P50/P95/P99
and successful/incomplete/unsuccessful counts in English and Simplified Chinese.
Summary calculation remains off the main thread; refresh remains explicit.

## Validation Contract

JVM tests cover exact durations, outcome classification, exception identity,
diagnostic failures, concurrency, repeated operations, privacy, missing events
and process-clock separation. Instrumentation exercises actual Android memory
queries through `MobileNativeAgent.executeAction`, receipt verification, a
controlled screen-timeout case and failed/replayed dispatches.

The real-device overhead comparison alternates 100 traced and 100 untraced
memory queries after warmup. Its gate allows no more than 10 ms additional P95
for tracing. This is an instrumentation overhead gate for that real operation,
not a universal model/tool/UI latency SLO. Functional test spans use an isolated
in-memory sink; the overhead benchmark uses the production asynchronous tracer
and journal in a dedicated test directory, including validation and queue writes.
Controlled recovery fixtures disable production timing so their artificial work
does not enter the user's diagnostic journal.

The full objective still needs provider/model-load, image/blob processing,
additional verification boundaries, UI frame and real end-to-end acceptance.
These four stages are a production integration step, not full tracing coverage.

## Verification (2026-09-10)

- Based on main `c390bc978`, including merged PR #2979. The first compile found
  a nullable callback invocation in the new recorder; it was corrected before
  any candidate was installed. Final app/test APK build passed in 6m39s.
- Full JVM: 3,505 tests in 505 suites, zero failures/errors, five skips.
  Repository checks, 73-library 16 KiB alignment and 24-library QNN packaging
  passed. No ASR/QNN implementation or model settings changed.
- SM-T575 was upgraded in place to 1.1.53 (939) at 15:21:37. Original install
  timestamp remained 2026-09-07 07:17:23; user data and pairing were retained.
- All seven timing/journal/layout device tests passed without skips in 9.2 s.
  This includes actual Android memory values, receipt-only observation,
  controlled observation timeout, replayed failure, blocked-writer behavior,
  clock separation and the existing three-line percentile layout.
- The initial in-memory-sink 200-query comparison measured baseline P95 6.8305 ms and
  traced-call P95 10.415693 ms, a 3.585193 ms difference within the 10 ms gate.
  The 100 internal dispatch spans measured P50 4.535115 ms / P95 9.705346 ms /
  P99 25.0325 ms. These internal spans exclude outer recorder setup; the paired
  caller measurements include it. Neither measures model or transport latency.
  This preliminary sample does not include the production journal queue; the
  final acceptance benchmark uses that queue and actual isolated file writes.
- The final production-journal benchmark and all four runtime timing cases
  passed in 3.518 s. Baseline P95 was 14.91827 ms; traced-call P95 was
  16.889231 ms, an additional 1.970961 ms. The 100 measured spans reported
  P50 11.354192 ms / P95 15.990269 ms / P99 20.458461 ms. No diagnostic events
  were dropped and no writes failed. Compare enabled/disabled samples within
  each interleaved run, not absolute values across different device states.
- The seven-class existing execution/recovery regression passed in 234.806 s:
  56 actual passes, 12 explicit lifecycle skips, zero failures. This ran against
  the unchanged release APK; the subsequent benchmark refinement changed only
  instrumentation code. The release APK hash remained identical.
- The final crash buffer was empty. A force-stop/Activity launch returned
  `Status: ok`, `WaitTime: 4314 ms` (one sample, not an end-to-end startup SLO).
  Manual navigation to the complete dashboard remains pending device unlock;
  the isolated percentile row layout test passed and no screenshot of the new
  rows is claimed.

APK SHA-256:
`E09654F4E6BBAC624D8F2BDF5EEF8E3B535F63D628BD8ACAB4E7C45EDEE052B3`.
Local evidence: `build/runtime-stage-build.log`,
`build/runtime-stage-final-build.log`, `build/runtime-stage-device.log`,
`build/runtime-stage-metrics.log`, `build/runtime-stage-16kb.log` and
`build/runtime-stage-qnn.log`.
Additional final evidence: `build/runtime-stage-production-journal-device.log`,
`build/runtime-stage-production-journal-metrics.log`,
`build/runtime-stage-regression.log`, `build/runtime-stage-journal-test-build.log`,
`build/runtime-stage-repo.log` and `build/runtime-stage-crash-buffer.log`.
