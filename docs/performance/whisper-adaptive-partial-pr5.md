# Adaptive Whisper Partial and Stable Text

PR-5 adds bounded streaming transcription for the verified Tiny and Base Whisper profiles. It builds on the stateful Runtime/Session API from PR-4 and keeps Final decoding authoritative.

## Decode scheduling

All live voice sessions in the Android activity share one bounded priority scheduler. Work is ordered as follows:

1. Current Final
2. Current Partial
3. Accuracy review
4. Second Pass
5. Benchmark
6. Background work

A Final request removes queued Partial work for the same voice session and aborts an active Partial before running. Session cancellation drops its queued work. The queue is bounded and rejects lower-priority work instead of growing without limit.

## Rolling audio windows

The audio hub keeps a bounded PCM ring buffer. A Partial request first asks the adaptive policy whether work is due; only then does it copy the newest window. It never re-decodes the full growing utterance on a fixed timer.

- Tiny starts at a 750 ms interval with an 8 second maximum window.
- Base starts at a 1.1 second interval with a 10 second maximum window.
- Partial is disabled for larger profiles; those profiles remain Final or Second Pass choices.
- Queue backlog immediately skips work and increases the interval.
- Real-time factor adjusts interval and window size. A sustained RTF above 1.5 disables Partial for that voice session while preserving Final.

## Stable text

Partial results retain timestamp, average log probability, and no-speech probability metadata. The stabilizer combines three signals:

- agreement with the previous hypothesis,
- segments outside the unstable tail,
- confidence and no-speech thresholds.

Repeated, safe prefixes render in the normal text color. The revisable suffix renders in the secondary text color. Exact character overlap prevents repeated text when a rolling window advances. Final performs one full authoritative decode, replaces provisional text, and clears the unstable suffix.

## App integration

Chat hold-to-talk, Agent hold-to-talk, and wake voice capture use the same live session contract. Chat and Agent input surfaces replace the waveform with live text after the first Partial. The existing voice coordinator receives structured Partial and Stable events. Final still passes through the coordinator's single `RouteFinalTranscript` guard, so a transcript is routed once.

Cancellation, no-speech timeout, capture failure, finalization failure, Activity destruction, and a new utterance all release session work. The shared scheduler is owned by the Activity and closes once at destruction.

## Security and privacy

- Rolling PCM and transcripts remain on device.
- Only a verified private model selected from the signed model catalog can decode.
- The scheduler request pins the model profile ID, preventing a settings change from silently switching a queued decode.
- Queue capacity, sample rate, audio duration, native handles, and cancellation remain bounded by the PR-3 and PR-4 contracts.

## Feature flag and rollback

`voice.whisper_adaptive_partial_v1` is enabled by default in debuggable builds and opt-in in release builds. Disabling it keeps PCM capture and Runtime v2 Final transcription unchanged; only live Partial and stable text are removed.

## Validation

- Final preempts an active Partial and executes exactly once.
- A bounded queue rejects lower-priority overflow work.
- Backlog and high RTF reduce Partial frequency and window size.
- Rolling snapshots contain only the newest requested duration.
- Repeated windows promote stable prefixes without duplicating overlap.
- Low-confidence or no-speech segments stay provisional.
- A second Final request for one live session is rejected before decode.
- Existing voice coordinator Final-route tests remain green.
- The full Android JVM suite completed 1,203 tests with zero failures and one skipped test.
- On the Samsung SM-T575 reference device, the bundled Tiny model completed a real Partial, adaptive Final, and independent authoritative Final. Both Final transcripts matched and all native runtime/session handles returned to zero.

Device validation records first-Partial latency, stable-text latency, Final latency, RTF, queue backlog, and duplicate Final count through the existing voice telemetry trace.
