# Device-Certified Whisper Runtime Policy

PR-6 replaces model-name assumptions with measurements from the current device, Android build, native runtime, model artifact, and fixed benchmark fixture. Tiny through Large v3 Turbo use the same certification and policy contracts.

## Benchmark protocol

An installed model starts as `INSTALLED_UNCERTIFIED`. The benchmark verifies the signed-catalog model file before native loading and then performs:

1. Device memory and thermal preflight.
2. Thread search over `2`, `3`, `4`, the detected high-performance core count, and `min(6, high-performance cores)`.
3. Repeated 3 and 5 second decoding for every candidate.
4. Three 10 second stability passes with the selected thread count.
5. Three native cancellation probes.
6. Transcript correctness, degradation, memory, CPU, energy, battery temperature, and thermal checks.

The bundled fixture is deterministic PCM16 at 16 kHz mono. It contains no user audio. The persisted report stores only correctness and technical measurements; it does not store decoded text or PCM.

Each measurement distinguishes cold and hot model loads and records RTF, first-Partial latency, Final tail latency, peak PSS/RSS/native heap, process CPU time, energy when Android exposes it, temperature, thermal status, and cancellation response.

## Certification key and invalidation

A certification is valid only for an exact key containing:

- manufacturer, device, and SoC;
- Android API level;
- app version code;
- whisper.cpp version and native build fingerprint;
- model profile ID and SHA-256;
- benchmark fixture version and SHA prefix.

Any key change makes the prior record stale. Stale evidence remains available for diagnosis but cannot select or configure the current native model.

## Certification levels

- `REALTIME`: warm RTF p95 at or below `0.80`, correct transcript, acceptable thermal state, and cancellation p95 at or below `300 ms`.
- `FINAL`: warm RTF p95 at or below `1.50` with the same correctness and safety gates.
- `SECOND_PASS`: stable local execution above the interactive RTF gate. There is no model-family or arbitrary RTF cutoff.
- `REMOTE_RECOMMENDED`: local memory, OOM, or thermal constraints make remote execution safer.
- `UNSUPPORTED`: model correctness, cancellation, corruption, or native compatibility failed.

Medium, Large, and Turbo can become real-time only when their measured evidence passes the same gates. Tiny and Base receive no automatic exemption.

## Runtime policy

The policy receives the user's mode, current certifications, network, memory, current PSS, thermal state, battery, charging state, foreground state, recent RTF, decode backlog, utterance duration, task risk, and remote permission.

It returns a provider, fast and accurate profiles, execution modes, Partial interval, thread count, Second Pass decision, and public rule reasons. It never emits private model reasoning.

- Automatic and Fast select only a current real-time certification.
- Privacy never selects a remote provider.
- Accurate can pair a real-time pass with a higher-quality certified Second Pass.
- Manual cannot bypass memory, thermal, remote-only, unsupported, or stale-certification gates.
- Backlog and moderate thermal pressure reduce threads and Partial frequency.
- Severe and critical thermal states disable progressively more local work.
- A thermal cooldown window prevents immediate large-model reload after the observed status drops.

Interactive voice input preempts a running benchmark. Cancellation closes its runtime and does not persist a partial certification. A second benchmark request fails fast instead of waiting behind the first and interfering with later voice capture.

## UI

The ASR model page exposes Automatic, Fast, Accurate, Privacy, and Manual runtime modes. Installed profiles show untested, benchmarking, stale, real-time, Final, Second Pass, remote-recommended, or unsupported status.

The certification detail includes RTF p50/p95, cold/hot load p95, first-Partial and Final-tail p95, peak PSS/RSS/native heap, selected threads, thermal status, cancellation p95, recommendation, and failure reason. Users can retest, but cannot force an unsafe certification into real-time mode.

## Storage and privacy

Certification JSON is stored in the app-private `filesDir/voice/whisper` directory using atomic replacement and bounded retention. Malformed records fail closed. No model path, user transcript, user audio, credential, contact, or message content is stored.

## Feature flags and rollback

- `voice.whisper_auto_benchmark_v1` controls benchmark and certification UI.
- `voice.whisper_policy_engine_v1` controls certified runtime selection.

Both default on in debuggable builds and off in release builds. Disabling policy selection leaves the verified Runtime v2 and existing selected-model behavior available. Disabling automatic benchmark leaves installed model files untouched.

## Validation

Unit coverage includes key invalidation, malformed-store recovery, evidence round-trip, RTF boundary classification, device-dependent model modes, memory and thermal fallback, backlog adaptation, manual-mode safety, OOM, native incompatibility, benchmark cancellation, cold/hot evidence, and thermal cooldown.

The bundled Tiny model was certified on a Samsung SM-T575 running Android API 33 with the `zh_cn_v2` fixture:

- certification: `REALTIME`, `REALTIME_PARTIAL`, 3 threads;
- warm RTF p50/p95: `0.231 / 0.232`;
- cold/hot load p95: `2328 / 2120 ms`;
- first-Partial/Final-tail p95: `2378 / 2499 ms`;
- peak PSS/RSS/native allocation: `504.5 / 527.6 / 743.8 MiB`;
- maximum thermal status: `0`;
- native cancellation p95: `9 ms`;
- 15 persisted measurements and no persisted transcript field.

The device instrumentation test rebuilt and installed both APKs, verified the bundled model, invalidated the earlier fixture key, completed certification in 43.34 seconds, and round-tripped the private evidence store. The Android voice-settings smoke test also verified runtime-mode persistence and the rendered ASR/TTS settings on the device.

The final gate ran 1,229 Android JVM tests with zero failures and one skipped test. Repository policy checks, the English-source boundary, native CMake compilation, and debug APK assembly also passed.
