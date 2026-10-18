# Desktop Whisper Medium default

Desktop 1.5.3 changes the Agent composer default from multilingual Whisper Base
to multilingual Whisper Medium at the user's request. CPU INT8 inference,
four-thread ceiling, offline-first cache loading, hold-to-record behavior,
draft appending and privacy cleanup remain unchanged.

The model is independent of Android/QNN, contact voice messages and remote
Whisper settings. `GALAXYSSI_COMPOSER_WHISPER_MODEL` remains an explicit
override. The previous 1.5.2 performance report describes the Base baseline,
not Medium latency.

The test machine already has a cached Medium snapshot with a 1,527,906,378-byte
model file. No replacement or deletion of the existing Base model is needed.
First-use model initialization and CPU transcription may take longer than
Base; measured behavior must not be inferred from the earlier Base timings.

Regression coverage verifies the Medium default, explicit model override,
offline cache preference, reuse across requests, and separation from remote
ASR configuration.

## Validation

- Desktop check: 88 tests and the structure check passed.
- Composer, STT bridge and remote Whisper regression suite: 25 tests passed.
- Real Electron fake-microphone -> Opus -> IPC -> local Whisper pipeline:
  both runs recognized the synthetic Chinese sentence, ended all audio tracks
  and returned to idle. Seven-second recordings took 23.53 seconds after
  release on the cold run and 22.05 seconds on the warm run on this machine.
  These samples demonstrate successful transcription, not a latency guarantee.
  Medium is materially slower than the Base baseline under this CPU setup.
