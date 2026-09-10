# Recovery transport tracing and paired-device observations

## Missing measurements

Recovery batches carry task identities inside `items`, not in a top-level
`task_id`. Both transport tracers previously ignored these batches because the
top-level task ID was blank. Lookup and publish-call timings alone could not
show durable queue residence, PUBACK, or peer-receipt timing.

Android 1.1.37 (923) and Desktop 1.1.40 attribute one batch transport sample to
its first well-formed identity. All identities and the route are checked before
attribution. The envelope is not mutated, ordinary task tracing is unchanged,
and contact chats remain excluded. This shape check is only telemetry selection,
not a replacement for authenticated protocol validation.

Debug Android builds also record a hashed query nonce and a fixed boundary code:
start, transport acceptance, accepted response, timeout, cancellation, wrong
Desktop/route, invalid batch, identity mismatch, duplicate, or late/unknown
response. No query body, answer, contact name, credential, or raw nonce is logged.
Diagnostic sink failure cannot change recovery or cleanup. Release builds do not
emit these diagnostic logs.

No timeout, retry policy, task identity, execution behavior, pairing, or queue
contents were changed by this tracing patch. A successful tracing-enabled run
must not be described as proof that telemetry fixed network latency.

## Automated verification

- Android: 3,401 tests in 493 suites; zero failures/errors, five existing skips.
- Backend: 172 tests passed, including transport hooks, ACK races, recovery
  controls, real encrypted queue capacity, and malformed batch cases.
- Repository guard and whitespace checks passed.
- APK: 73 AArch64 libraries passed 16 KB alignment checks.
- QNN package: 24 libraries, 221.68 MiB uncompressed, passed package checks.

Build: `build/recovery-transport-trace-build.log` (6m13s).
Backend: `build/recovery-transport-trace-expanded.log`.
APK SHA-256:
`A0250BA7D9B8A9DEBD95DED2B425C6C8505E4496DA0B63A32BBA95F310CBA132`.

## T575 live evidence

Only `SM-T575` was attached. Android was updated in place, retaining its original
installation, data, and paired identity. Desktop was gracefully restarted only
after confirming normal and control execution pools were idle. MQTT, sidecar,
and all ten subscriptions were verified ready.

The existing completed test source 13466 was queried read-only. No model task,
tool execution, file modification, or synthetic result was submitted. Its
conversation still contains the same two completed Desktop task records.

| Run | Verified observation time | Result |
| --- | ---: | --- |
| Desktop tracing with previous Android | 3,994 ms | completed, read-only |
| Both tracers, cold instrumentation 1 | 5,017 ms | completed, read-only |
| Both tracers, cold instrumentation 2 | 5,188 ms | completed, read-only |
| Both tracers, cold instrumentation 3 | 7,730 ms | completed, read-only |

The production eight-second query timeout was unchanged. The three cold
instrumentation runs include no wait for an Agent reply; they inspect a saved
task. The test's observation timer additionally includes binding/decoding work,
so it differs slightly from the inner query span.

Monotonic stage ranges from the three tracing-enabled observations:

| Stage | Observed range |
| --- | ---: |
| Phone queued to dispatch | 7.07-8.77 ms |
| Phone publish to broker ACK | 1,265.85-2,287.33 ms |
| Phone queued to returned peer receipt | 3,466.34-4,101.34 ms |
| Desktop task lookup | 10.25-11.87 ms |
| Desktop response queued to dispatch | 125.14-1,692.59 ms |

The peer-receipt interval includes the return receipt and is not one-way network
latency. Every interval is computed within one clock/process and operation;
phone and Desktop wall clocks are not subtracted. Retransmission attempts have
separate operation IDs. These few samples are not a P95/P99 acceptance result.

One `late_or_unknown` response was observed while another query was active.
It did not complete or replace the active query. That code does not distinguish
a timed-out request from another unregistered nonce; it must not be interpreted
as a stronger diagnosis without matching additional evidence.

Evidence:

- `build/recovery-transport-trace-desktop-only-live.log`
- `build/recovery-transport-trace-live-{1,2,3}.log`
- `build/recovery-transport-trace-live-{1,2,3}-diagnostic.log`
- `build/recovery-transport-trace-live-phone-points.json`
- `build/recovery-transport-trace-live-desktop-points.json`
- `build/recovery-transport-trace-live-metrics.json`

## Remaining acceptance

Earlier paired queries timed out; subsequent successes do not establish that
all underlying causes are eliminated. Cold recovery is still above five seconds
in several samples. Expired observation traffic, public-broker variability,
full archived-body/UI recovery, ordinary Agent Loop restart, and external-effect
deduplication still require their full failure/restart matrices. The overall
Run Kernel, tracing, and chaos objectives remain incomplete.
