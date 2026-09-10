# Android image stage tracing

## Scope

Agent image preparation uses the existing bounded, content-free latency journal.
Cloud vision dispatch passes `connectorTaskId`; inline MQTT dispatch passes
`resolvedTaskId`; reliable attachment preparation passes `scope.taskId`.
These are the same task identifiers used by the corresponding dispatch paths.
Each span uses an opaque task hash, a unique operation ID and the process-local
monotonic clock. Multiple images and repeated attempts cannot overwrite one
another's samples. Independent images share the task trace, not an operation ID.

| Metric | Actual measured work |
| --- | --- |
| `phone_runtime_image_prepare_ms` | One complete `encodeForTransport` call, including budget validation and cleanup |
| `phone_runtime_image_original_probe_ms` | Existing size check and bounded original-byte read, when necessary |
| `phone_runtime_image_decode_ms` | Bounds decode, sampled decode, EXIF orientation and dimension limiting |
| `phone_runtime_image_encode_ms` | Alpha flattening, JPEG quality search, dimension reductions, fallback encoding and bitmap recycling |

The prepare span encloses the other stages. Do not add its duration to the
substage durations. A known oversized image may finish its original-byte probe
without I/O. A probe miss is not a failed request: decoding is the existing next
step. Images that fit the budget retain their original bytes and do not emit
decode/encode samples. Failed decode or exhausted budgets are unsuccessful
samples, excluded from successful percentiles. Process death leaves incomplete
spans rather than fabricated completion measurements.

## Invariants

- The 100,000-byte Agent transport ceiling, dimension limits, quality search,
  orientation correction and retry loop are unchanged.
- Contact original-image transmission still bypasses this compression pipeline.
- Preview loading is not instrumented by this change; it has no reliable Agent
  task identity and must not contaminate transport preparation statistics.
- No OCR, provider selection, ASR, QNN, network retry or pairing behavior changes.
- No file names, URIs, attachment contents or prompts enter the timing journal.
- Telemetry exceptions cannot suppress, retry or replace image processing.
- Journal writes remain asynchronous. There is no new wait, executor or lock
  around image processing, and no image work moves onto the UI thread.
- Unscoped callers keep timing disabled instead of inventing a task identity.

## Verification

`AgentImageTimingDeviceTest` exercises real Android image APIs for small PNGs,
large JPEGs with EXIF rotation, missing files, corrupt bytes, exhausted budgets,
concurrent tasks and failing telemetry sinks. It compares encoded bytes with
timing disabled, not just byte counts or mocks.

The production-journal benchmark alternates 20 enabled and 20 disabled real JPEG
preparations after warmup. It checks all four phase counts and journal health.
Its relative overhead gate is enabled P95 <= disabled P95 * 1.10 + 10 ms. This is
a tracing overhead gate for that input/device, not a camera-image latency SLA or
an end-to-end model response performance claim.

Existing original-image transport and encrypted thumbnail tests cover the
contact path that must remain unaffected. Real provider/network timing, preview
render latency and comprehensive device/input-size performance gates remain
separate acceptance work.

### T575 results, 2026-09-10

Android 1.1.54 (940) was installed in place on SM-T575 (`R52R90282TY`), retaining
the original 2026-09-07 installation. No user data or pairing was reset.

- Full JVM suite: 3,505 tests / 505 suites, zero failures/errors, five skips.
- Image timing, existing encoding, contact originals and thumbnail/transfer
  recovery: 12 actual device passes, no skips or failures.
- Existing runtime timing and journal regression: seven actual device passes.
- Native package gates: 73 AArch64 libraries pass 16 KB alignment; QNN package
  verification passes.
- Crash buffer was empty after the tests.

The production-journal benchmark used a generated 800 x 600 JPEG. Disabled-call
P95 was 100.891539 ms; enabled-call P95 was 105.211577 ms, a difference of
4.320038 ms. All four stages had 20 complete successful samples, with zero
journal drops or write failures.

| Stage | P50 (ms) | P95 (ms) | P99 (ms) |
| --- | ---: | ---: | ---: |
| Preparation | 99.91 | 104.64 | 108.74 |
| Original probe | 0.14 | 0.55 | 0.89 |
| Decode/orientation | 14.90 | 16.19 | 25.05 |
| Compression/encoding | 82.86 | 86.74 | 87.00 |

These small-sample percentiles describe this benchmark only. They do not prove
general camera-image, provider or UI SLOs. Activity launch returned `Status: ok`,
but the device was still on the system lock screen, so actual performance-page
navigation and visual inspection remain unverified.

Local evidence: `build/image-stage-build.log`, `build/image-stage-device.log`,
`build/image-stage-metrics.log`, `build/image-stage-timing-regression.log`,
`build/image-stage-repo.log`, `build/image-stage-16kb.log`,
`build/image-stage-qnn.log`, and `build/image-stage-crash.log`.

Installed APK SHA-256:
`E0A846AED308289826C6E9C0A21B936E4B4C75E55512F98809079B67C86AF432`.
