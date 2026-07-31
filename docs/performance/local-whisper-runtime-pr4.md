# Local Whisper Runtime and JNI v2

PR-4 replaces the local voice-command decode path with an explicit Runtime/Session API over 16 kHz PCM16. The implementation keeps the vendored whisper.cpp 1.9.1 release, arm64 CPU execution, and the legacy file API as a feature-flag rollback path.

## Runtime contract

- A process loads at most one verified Whisper model.
- A runtime owns the native model context and creates session-scoped `whisper_state` handles.
- A session is used for one decode and is closed explicitly.
- A model switch aborts and closes all sessions before releasing the old context.
- Native handles are opaque monotonic IDs backed by guarded `shared_ptr` registries; Java values are never treated as native pointers.
- Native decode is serialized across sessions so a model context and state are never used concurrently.

The same runtime accepts every verified catalog profile. Tiny, Base, Small, Medium, Large v3, and Large v3 Turbo therefore share one decode implementation. Whether a profile can complete on a device remains subject to its memory budget and the later benchmark policy.

## Audio and result path

New `AudioRecord` captures are sent directly to JNI as 16 kHz PCM16. The compatibility file entry point still decodes WAV or encoded audio on Android before entering the same runtime, but it is no longer the main local command path.

JNI returns structured error codes, detected language, timestamped segments, average log probability, no-speech probability, sample/encode/decode timings, total latency, and real-time factor. State-specific timing access was added narrowly to the vendored whisper API without changing its upstream version.

## Cancellation and ownership

Kotlin cancellation, a new utterance, session close, model switch, runtime unload, thermal pressure, timeout, upstream selection, and memory pressure can set the native atomic abort flag. The callback is installed on every scheduled CPU graph, including convolution, encoder, cross-attention, and decoder graphs.

On the Samsung SM-T575 reference device with the verified bundled Tiny model:

- 20 in-compute cancellation samples: 41, 6, 12, 11, 14, 7, 7, 7, 7, 6, 9, 7, 6, 7, 7, 7, 7, 9, 8, 11 ms.
- Cancellation p95: 14 ms, below the 300 ms acceptance limit.
- 30 consecutive real native recognitions: every session handle returned to zero after close.
- Sampled native heap after each five recognitions: 100240824, 99311928, 99277192, 99376216, 99204984, 99227736 bytes.
- First-to-last native heap change: -1013088 bytes; no sustained growth was observed.
- The installed Small profile completed a real Final decode through the same Runtime/Session path. The installed Medium profile was correctly skipped because 1.88 GB available memory was below its pinned 3 GB safety threshold.

## Security and privacy

- Runtime loading accepts only files resolved through the verified private model manager from PR-3.
- PCM stays on device in the local path.
- Input ranges, duration, thread count, language, prompt length, and handle validity are bounded before native use.
- Closing a runtime invalidates all child handles and aborts in-flight work before the context can be freed.
- No finalizer is used for normal ownership; Runtime, Session, and the legacy compatibility context expose explicit close/release operations.

## Feature flag and rollback

`voice.local_whisper_runtime_v2` is opt-in in release builds and enabled by default only in debuggable builds. Turning it off routes local file/PCM input through the retained `WhisperContext` compatibility implementation. This rollback does not remove downloaded models or alter chat and Agent state.

## Validation

- JVM lifecycle, model switching, structured result, benchmark, PCM validation, and 30-session tests.
- On-device verified Tiny load, decode, explicit release, cancellation p95, and 30-recognition native-memory tests.
- Android debug application and instrumentation APK builds, native arm64 build, repository checks, and voice smoke checks.

PR-5 can now add Tiny/Base adaptive partial decoding and stable-prefix text without changing native model ownership.
