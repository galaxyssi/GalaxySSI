# Continuous listening completeness

## Scope

Android 0.1.6.36 (1412), based on main 3ea3a9fb5. Desktop is unchanged.

- Continuous conversations wait for 1,000 / 1,200 / 1,400 ms of trailing
  silence for short / medium / long spoken spans. Silence cannot change its
  own duration bucket. Ordinary command profile values remain unchanged.
- An idle duplex listener uses the measured noise floor for quiet speech.
  Neural speech classification and onset confirmation remain required.
  Active playback retains the previous amplitude floor and AEC/route checks.
- Onset confirmation tolerates up to 60 ms of unvoiced gaps, but requires
  180 ms of positive evidence and at least 75% speech occupancy. Isolated
  bursts cannot accumulate indefinitely. Playback transitions reset candidates.
- QNN startup/segment backlog overflow marks the result incomplete. The
  submission path then uses retained full PCM instead of a truncated fast
  result. Owned queued PCM copies are zeroed on consumption, eviction or close.
- The selected ASR model, contact voice-message encoding, input/output text
  separation, and explicit microphone stop behavior are unchanged.

## Verification

Validated on SM-S9480 (S26U), with the existing large_v3_turbo QNN model and
microsoft_edge TTS. Replacement installation preserved app data and settings.
No model download, private recording upload, or volume adjustment was used.

| Check | Result |
| --- | --- |
| JVM audio, local ASR and Agent voice regressions | 227 passed, 0 failed/skipped |
| Android debug app and instrumentation build | Passed |
| Repository checks and diff whitespace check | Passed |
| Neural VAD instrumentation | 3 passed |
| Installed QNN end-to-end fixture | 1 passed |
| Live microphone and continuous-listening instrumentation | 4 passed |

The bundled, project-authored synthetic Chinese fixture was accepted at normal
and quiet levels and with added noise by both neural VAD and the combined onset
gate. Silence, white noise, fan hum, a notification tone and clicks produced
zero confirmed onsets. VAD frame P95 was 0.166 ms in this run (maximum 0.302 ms).

The 15.84-second Chinese fixture with an inserted 700 ms pause was streamed to
the installed QNN runtime. It returned the full observed sentence, including
all eight benchmark keywords; input and decoder completeness were both true.
The 17.630-second measurement includes paced delivery of the recording and
the added pause, not just decoder latency.

Physical microphone tests verified that waiting, Microsoft TTS playback and
completion retain one protected capture without creating echo input turns;
noise-only manual submission preserves the draft; stopping cannot rearm the
microphone; and communication-mode recovery and 50-second monitor renewal
preserve the current turn. The microphone was released at test completion.

## Limits

This is not a population-level CER/WER benchmark. Accent diversity, far-field
human speech, severe noise and multiple headset models still require broader
acoustic evaluation. Endpoint patience adds approximately 150-900 ms compared
with the old continuous-listening profile, depending on utterance length.
The existing 60-second utterance boundary remains in place.

Local evidence is kept in the ignored build directory:

- `build/voice-listening-completeness-build.log`
- `build/voice-listening-s26u-model-tests.log`
- `build/voice-listening-s26u-microphone-tests.log`
- `apps/android/app/build/test-results/testDebugUnitTest/`
