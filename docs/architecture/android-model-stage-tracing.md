# Android local-model stage tracing

## Process ownership

Local LLM inference runs in `:local_model_runtime`. Only the caller process writes
the bounded Agent latency journal. A request carries an opaque task trace and
backend identifier over the existing private Binder protocol. The worker sends
small content-free timing events with that request ID. Timing events never set
the pending response, remove a pending request, or complete inference.

The caller accepts events only for an existing pending request with its exact
trace/backend, a known model stage, a nonempty operation ID and a valid bounded
record. Worker clock IDs and monotonic timestamps are retained. No duration is
constructed by subtracting timestamps from different process clock domains.
Events arriving after terminal response/connection cleanup are ignored.

Model stage objects are explicit request scopes rather than thread-local state,
so coroutine dispatcher changes and Binder execution cannot inherit a different
conversation's trace. The normal local web/tool path passes its existing task ID
through cooperative planning, answer and fallback inference. Taskless callers
receive independent opaque invocation IDs; those samples are not claimed as
end-to-end traces of an existing Agent task.

## Stages

All metrics have the `phone_model_` prefix and `_ms` suffix.

| Stage | Boundary |
| --- | --- |
| `request` | Caller-side local inference attempt, including eligibility checks and failures |
| `client_lock_wait` | Waiting for the caller runtime lock, ending immediately on acquisition |
| `service_bind` | Actual `ensureConnected` operation |
| `process_roundtrip` | Binding, Binder generation transaction, response and success validation |
| `service_queue` | Worker receipt to its executor starting the request |
| `worker_lock_wait` | Worker runtime lock acquisition |
| `preflight` | Verified artifact lookup, configured context and existing resource checks |
| `sdk_init` | GenieX SDK initialization callback completion |
| `load` | Actual llama load or GenieX artifact/wrapper creation; includes old model cleanup |
| `reuse` | Existing compatible loaded model selected without a load |
| `generate` | Native generation through nonempty reply validation |
| `first_token` | QNN generation start to first actual nonempty token event in the worker |
| `release` | Existing post-inference worker release operation |

Request, round-trip and internal stages are nested: their durations must not be
added together. Repeated/concurrent invocations have separate operation IDs.
Failures, cancellation and timeouts are excluded from successful percentiles;
observed starts without an end remain incomplete. A later generation failure
does not erase an already observed first token.

## Preserved behavior and limits

- No changes to models, quantization, context, sampling, model selection, native
  inference APIs, ASR priority, mutex ownership, unloading or service timeouts.
- The service still releases local LLM allocations before sending its response.
  Consequently a sequence of normal requests is not automatically a warm-model
  benchmark. A reuse sample requires the actual loader reuse branch to execute.
- Whisper loading/residency and the existing voice metrics are unchanged.
- No prompt, output text, artifact path, file name or credential enters a timing
  record. No timing journal is uploaded to a provider or another device.
- Timing sinks are best-effort and cannot retry, replace or suppress model work.
- Service events are stage boundaries, not per-token log messages. Only the
  first nonempty QNN token emits the first-token finish event.
- The existing llama generation API does not expose a token callback. This
  change does not fabricate llama TTFT from total generation time.
- QNN first-token timing is a worker observation, not first text drawn on screen.
  Real token streaming to the conversation UI remains separate acceptance work.

## Tests and acceptance boundaries

`AgentModelTimingTest` covers exact stage durations, cold/reuse separation,
terminal outcome preservation, exceptions, coroutine dispatcher changes,
cross-request validation, malformed records, worker clock separation, partial
spans after restart and concurrent invocations.

`AgentModelTimingDeviceTest` binds the actual local-model service and sends real
generation requests against unavailable CPU/QNN profiles. It verifies natural
failure, worker event delivery to the caller journal, clock separation, and that
timing events do not complete requests or replace their errors. Tests require an
empty installed-LLM inventory and never change model settings or download data.

This failure-path suite does not demonstrate successful llama/QNN model loading
or inference speed. Real installed-model cold/warm, TTFT, memory and sustained
performance gates still require supported models and target hardware. The
cancelled large Qwen download is not resumed by these tests.

### Verification on 2026-09-10

- Android 1.1.55 (941) built successfully with all JVM tests: 3,513 tests across
  506 suites, zero failures/errors, five skips.
- The three model timing device tests passed on SM-T575 (`R52R90282TY`) with no
  skips. Real llama/QNN service requests returned their existing unavailable
  model failures; worker queue/release events reached the caller journal with
  their own clock IDs. No successful load/generation samples were manufactured.
- All 19 image pipeline, contact original/thumbnail/transfer, runtime timing and
  journal regression tests passed on the same device, with no skips.
- Repository guard, 73-library 16 KB alignment and 24-library QNN package checks
  passed. The crash buffer was empty after testing.
- Installed in place at 16:17:49 local time; the 2026-09-07 first installation
  timestamp was retained. No user data, pairing or model settings were reset.
- Actual model cold/warm loading, QNN first-token performance and manual
  performance-page visual acceptance remain unverified. The device has no
  installed local LLM, and its system lock screen prevents manual page review.

Local evidence: `build/model-stage-build.log`, `build/model-stage-device.log`,
`build/model-stage-regression.log`, `build/model-stage-repo.log`,
`build/model-stage-16kb.log`, `build/model-stage-qnn.log` and
`build/model-stage-crash.log`.

Installed APK SHA-256:
`A5A3F7945DAA5269CB120D1F05A353E487F1AC44A1B665BFC21931F21F06E7E5`.
