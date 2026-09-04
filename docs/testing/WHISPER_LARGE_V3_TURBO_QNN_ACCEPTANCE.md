# Whisper Large-v3-Turbo QNN Acceptance Matrix

This document traces the GalaxySSI high-accuracy local ASR implementation to the
Whisper Large-v3-Turbo QNN specification. It separates host-verifiable behavior
from evidence that can only be collected on the target Samsung Galaxy S26 Ultra.

## Status legend

- **PASS**: implementation and automated non-device evidence are present.
- **DEVICE**: implementation is present; physical-device evidence is still required.
- **FALLBACK**: the target is intentionally rejected and a supported backend is selected.

## Non-device acceptance

| Area | Status | Implementation evidence | Automated evidence |
| --- | --- | --- | --- |
| S26 Ultra model identity | PASS | `LargeTurboQnnModelManifest.kt`, `AndroidLargeTurboQnnDeviceCapabilityDetector.kt` | `LargeTurboQnnModelLifecycleTest`, `LargeTurboQnnDevicePolicyTest` |
| QAIRT 2.45 model context, QNN runtime 2.47, and HTP v81 contract | PASS | `LargeTurboQnnModelManifest.kt`, `WhisperQnnContextAssets.kt`, `build.gradle.kts` | `WhisperLargeTurboQnnContractTest`, QNN APK package audit |
| Official context archive identity | PASS | pinned source URL, size, ETag, QAIRT release, and chipset metadata in `LargeTurboQnnModelManifest.kt` | manifest and downloader lifecycle tests |
| Resumable background download | PASS | `LargeTurboQnnModelDownloadService.kt`, `LargeTurboQnnModelDownloader.kt` | interruption, cancellation, resume, and source-identity tests |
| Model integrity and atomic install | PASS | archive SHA-256 receipt, entry CRC/size checks, per-file SHA-256, atomic release pointer, quarantine, and rollback in `LargeTurboQnnModelStore.kt` | `LargeTurboQnnModelLifecycleTest` including digest-receipt tampering |
| Audio capture | PASS | `AndroidPcmRecorder.kt` uses `AudioRecord`, mono PCM16, direct buffers, `VOICE_RECOGNITION` with `MIC` fallback | JVM contract tests and native frontend tests |
| 16 kHz and 48 kHz input | PASS | native sinc resampler in `audio_resampler.cpp`; 48 kHz device fallback | chunk-invariance and anti-aliasing native tests |
| Ring buffer | PASS | `audio_ring_buffer.cpp` | wraparound and capacity native tests |
| VAD segmentation | PASS | `vad_engine.cpp` with start debounce, pre-roll, end silence, post-roll, minimum and maximum segment limits | boundary, short-segment, and maximum-segment native tests |
| Long utterance stitching | PASS | `WhisperTranscriptAssembler.kt`, rolling segment logic | `WhisperTranscriptAssemblerTest` and native rolling-window tests |
| 128-bin Log-Mel | PASS | fixed `128 x 3000` extraction and silence padding in `log_mel_extractor.cpp` | Log-Mel dimensions, silence, and mel-filter validation native tests |
| NEON feature acceleration | PASS | ARM NEON Hann-window and filter accumulation paths in `log_mel_extractor.cpp` | host scalar-path parity plus Android native build |
| Persistent QNN runtime | PASS | `WhisperLargeTurboQnnRuntime.kt`, `OrtWhisperQnnNetwork.kt` | runtime and session policy tests |
| Persistent tensor and KV arenas | PASS | direct tensor arena plus self/cross KV caches in `OrtWhisperQnnNetwork.kt` | QNN network contract tests |
| HTP shared memory option | PASS | `enable_htp_shared_memory_allocator` gated by `libcdsprpc` availability | `QnnHtpSessionPolicyTest` |
| No silent CPU fallback | PASS | QNN-only provider setup and fail-closed execution attestation | `QnnExecutionAttestationTrackerTest` |
| Warm-up before recognition | PASS | persistent runtime performs a silence warm-up | `WhisperLargeTurboAsrEngineTest` |
| Tokenizer-derived prompt IDs | PASS | `WhisperTiktokenTokenizer.kt` loads tokenizer and generation configuration assets | `WhisperTiktokenTokenizerTest` |
| Greedy transcription | PASS | beam size 1, temperature 0, bounded token generation, no timestamps | `WhisperGreedyTranscriberTest` |
| Chinese and automatic language modes | PASS | Chinese is explicit and auto mode is selectable; translation is not exposed as Turbo transcription | transcriber and contract tests |
| Pseudo-streaming windows | PASS | first partial, update cadence, overlap, active window, and final flush in `rolling_window.cpp` | rolling and adaptive-window native tests |
| Stable and unstable text | PASS | longest-common-prefix and two-pass stabilization | `WhisperTextStabilizerTest`, `WhisperTwoPassStabilizerTest`, native UTF-8 stabilizer tests |
| Single global ASR turn | PASS | `HighAccuracyLocalAsrTurn.kt` and controller-level ownership | `HighAccuracyLocalAsrTurnTest` |
| Thread isolation | PASS | dedicated audio, feature, QNN, and callback execution paths; serialized QNN inference | `WhisperDecodeSchedulerTest`, bounded feature-mailbox tests |
| Lifecycle handling | PASS | background, microphone permission, call state, audio focus, thermal state, and power saver monitoring | `LocalAsrLifecycleCoordinatorTest`, `AdaptiveAsrRuntimePolicyTest` |
| Thermal adaptation | PASS | balanced 900 ms cadence, 1,200 ms sustained-use cadence, and final-only severe mode | adaptive partial and runtime policy tests |
| Compatibility fallback | FALLBACK | incompatible S26 context binaries are never force-loaded; Base/Small QNN, whisper.cpp, and system ASR are ordered recovery options | device policy and preparation recovery tests |
| Offline privacy | PASS | the transcription path consumes local PCM and local model assets without an upload transport | dependency and request-path inspection; Android unit suite |
| Android 16 KB compatibility | PASS | native linker configuration and packaging policy | `npm run check:android:16kb` |

## Target-device acceptance still required

The following claims must not be marked complete from host tests or metadata alone.

| Acceptance ID | Required S26 Ultra evidence | Pass threshold |
| --- | --- | --- |
| DEV-NPU-01 | QNN profiling receipt for encoder execution | 5,026 of 5,026 layers on NPU; zero CPU/GPU fallback |
| DEV-NPU-02 | QNN profiling receipt for decoder execution | 1,213 of 1,213 layers on NPU; zero CPU/GPU fallback |
| DEV-LAT-01 | warmed encoder benchmark | P50 <= 300 ms; P95 <= 360 ms |
| DEV-LAT-02 | warmed decoder benchmark | P50 <= 7 ms/token; P95 <= 9 ms/token |
| DEV-LAT-03 | microphone-to-first-partial benchmark | P50 <= 1.4 seconds |
| DEV-LAT-04 | end-of-speech-to-final benchmark | P50 <= 900 ms |
| DEV-STAB-01 | continuous recognition soak | 30 minutes without crash or system kill |
| DEV-STAB-02 | permission, call, Bluetooth, foreground, and background transitions | no crash; deterministic pause/resume/fallback |
| DEV-THERM-01 | sustained thermal and power trace | adaptive cadence engages without corrupting transcripts |
| DEV-MEM-01 | peak process memory trace | no low-memory kill; recovery remains available |
| DEV-ACC-01 | 600-sentence Mandarin evaluation set | CER, first-token latency, final latency, repetition, rollback, temperature, power, and memory recorded |

## Required commands

Run these commands from the repository root before target-device acceptance:

```text
npm run test:android:asr-native
npm run check:android
npm run check:android:qnn-package
node tools/dev/check-no-chinese-outside-i18n.js
git diff --check
```

`npm run test:android:asr-native` builds the pure C++ frontend on the host and
runs the ring-buffer, resampler, VAD, rolling-window, Log-Mel, stabilization,
and queue tests through CTest. `npm run check:android` runs the complete JVM
suite, assembles the debug APK, audits 16 KB native-library alignment, and
verifies the complete pinned QNN/HTP runtime package. Packaging details and the
Qualcomm license boundary are documented in
`docs/setup/android-qnn-packaging.md`.

## Physical acceptance procedure

1. Install the release candidate on the target S26 Ultra.
2. Download and activate the official high-accuracy QNN package from the model UI.
3. Export the model-install receipt and verify the displayed release, QAIRT, HTP,
   archive SHA-256, and installed-file hashes.
4. Run the NPU and latency benchmark with the model already loaded and warmed.
5. Run the lifecycle fault matrix and the 30-minute soak.
6. Run the six 100-sentence accuracy groups defined by the product specification.
7. Export the signed benchmark report and attach it to the release evidence.

Until those seven steps pass, the product may report that the QNN backend is
available, but it must not claim measured S26 Ultra latency, accuracy, power, or
full-layer NPU coverage.
