# Voice and Remote Agent Latency Baseline (PR-0)

## Scope

This report establishes the measurement baseline required by the GalaxySSI Deep Latency Optimization Specification v2.0. The specification's original audit commit is `c980c5a0a58fc0300bbdf047a9ed5ed3ca9bf9d0`; implementation was rebased onto `d69ad8306bbc06d5a549c6638952817e3b6d29f9`, the latest `origin/main` available for PR-0. It does not claim that the optimized latency targets have been reached.

PR-0 adds content-free instrumentation only. Audio capture, ASR selection, model routing, response delivery, TTS playback, Agent execution, permissions, and user-visible behavior remain on their existing paths.

## Reported baseline

The specification and prior device observations identify three user-visible delay envelopes:

| Path | Reported envelope | Why the current path can be silent |
|---|---:|---|
| Local voice command | About 30 seconds in slow cases | Recording must stop before AAC/M4A decoding begins; the complete file is decoded and resampled; one full `whisper_full` inference runs before final text is available. |
| Cloud model response | About 10 seconds | The client uses a non-streaming JSON response. Connection, provider generation, the complete response body, JSON parsing, and any tool round must finish before text becomes visible. |
| Remote Agent result | About 90 seconds in long cases | MQTT delivery, Desktop queueing, Agent startup, tool work, and result delivery are distinct phases, but the previous latency data did not provide a single monotonic trace across them. |

These values are reported baselines, not newly fabricated benchmark percentiles. PR-0 creates the instrumentation needed to replace them with reproducible p50/p90/p95/p99 measurements.

## Code-confirmed stage decomposition

### Existing MediaRecorder and endpoint path

The current voice-command path records MPEG-4/AAC to an M4A file and checks `MediaRecorder.maxAmplitude` every 250 ms. It uses:

- approximately 3 seconds before declaring that no speech was detected;
- approximately 3 seconds of silence after detected speech;
- a 30-second maximum recording duration.

The new trace separates:

```text
microphone_open_started -> microphone_opened
speech_started -> speech_ended
speech_ended -> asr_final_started
```

For hold-to-talk, `speech_started` represents the recording press because the existing path has no VAD. For wake-command recording, it represents the first amplitude threshold crossing.

### Existing local Whisper path

`LocalWhisperAsr` still performs the same operations in the same order:

```text
M4A decode and 16 kHz mono resample
-> optional model load
-> complete whisper_full inference
-> Chinese script normalization
-> final transcript
```

PR-0 records decode, cold model load, full inference, audio duration, thread count, and real-time factor independently. No transcript or audio content is written to diagnostics.

### Existing cloud model path

`CloudModelClient` still sends non-streaming requests. Its existing HTTP limits are 20 seconds for connection and 60 seconds for response reads. The new events distinguish:

```text
model_request_started
-> model_connected
-> model_first_delta
-> model_request_completed
```

In PR-0, `model_first_delta` means the first response-body bytes were received. It is not yet a user-visible streaming token. The UI still receives text only after the full provider response and JSON/tool processing complete. PR-5 will introduce true model streaming.

### Existing TTS path

Microsoft Edge TTS still buffers the complete MP3 response before `MediaPlayer` playback. PR-0 records WebSocket connection, first audio bytes, playback start, and completion. Android system TTS records request and utterance start/completion callbacks.

### Existing remote Agent path

The existing control plane and task manager remain unchanged. The shared `traceId` now records:

```text
Android agent_run_create_started
Desktop agent_queue_entered
Desktop agent_run_started
Android agent_run_accepted
Desktop/Android agent_first_progress
Desktop/Android agent_first_partial_result
Desktop/Android agent_completed
```

The Desktop timings use `time.monotonic_ns()`. Existing durable task timestamps and delivery traces continue to use wall-clock values for history and protocol compatibility, but they are no longer used for the new latency calculations.

Android and Desktop monotonic clocks have unrelated origins. The shared `traceId` correlates their records, but latency is calculated only between events recorded on the same host. Cross-device transport latency continues to use the existing send/receive delivery evidence until a clock-offset-safe protocol is introduced.

## Diagnostic data

Diagnostics include only technical metadata such as model profile, provider, execution mode, network class, audio duration, RTF, thermal state, battery state, task status, and sanitized error category.

They exclude:

- PCM or encoded audio;
- transcript and response text;
- prompts and tool arguments;
- file paths, contacts, amounts, API keys, and URLs.

Android stores a rotating JSONL trace in the App-private diagnostics directory. Desktop stores a rotating JSONL trace under `~/.galaxyssi/diagnostics`. Both retain at most the current and previous 2 MiB segment. Exported reports explicitly state `content_included: false`.

Desktop export command:

```powershell
python apps/desktop/core/galaxyssi-link/backend/export_voice_latency.py --output voice-latency.json
```

Android exposes `VoiceLatencyTelemetry.exportContentFreeDiagnostics(context)` for a user-initiated diagnostics surface. PR-0 does not add an automatic upload.

## Feature flags and rollback

- Android preference: `voice.latency_tracing_v1`, enabled by default.
- Desktop environment flag: `GALAXYSSI_VOICE_LATENCY_TRACING_V1`, enabled by default.

Set the Android preference to `false` or set the Desktop environment variable to `0` to disable all new trace writes without changing the voice or Agent paths. Removing the tracer calls is not required for rollback.

## Measurement protocol for subsequent PRs

Collect cold and warm runs separately. Each scenario should include at least 30 successful samples and record failures, cancellations, fallback, battery, thermal state, model identity, and network class. Report p50/p90/p95/p99 rather than a single best run.

Required scenarios:

1. 3-8 second Chinese voice input using bundled tiny Whisper.
2. Cold and warm local model load.
3. Each configured cloud provider with and without a tool round.
4. Microsoft Edge TTS and Android system TTS.
5. Remote Codex, Hermes, Claude Code, OpenClaw, and Local LLM where available.
6. Wi-Fi, cellular, reconnect, cancellation, timeout, and provider failure.

The first optimization PR after this baseline must compare its results against these stage boundaries and must not substitute perceived UI activity for real provider or Agent events.
