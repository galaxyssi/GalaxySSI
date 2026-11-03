# Desktop local voice input

Desktop version: 1.5.2. Android and remote Whisper/QNN profiles are unchanged.

## Root cause and behavior

The Agent composer called `SpeechRecognition`/`webkitSpeechRecognition`. This
requires a browser speech service that ordinary Electron distributions do not
provide. The existing UI smoke replaced that API with a fake, so it did not
exercise recording or recognition. Contact voice messages already used a
separate MediaRecorder path and remain audio messages.

The Agent composer now records while held, cancels when dragged upward, and
transcribes on release. Recognition appends to the current draft; it does not
send the draft. Navigation, window blur and lock/sensitive-state cleanup cancel
capture and invalidate late results. Recording and recognition disable Send.

Audio travels as binary over authenticated loopback IPC/HTTP to faster-whisper.
It is not sent to a cloud ASR service, MQTT, a contact or an Agent. Inference
runs outside the FastAPI event loop. Audio is bounded to 8 MiB / 120 seconds,
not written to a temporary file, and owned mutable PCM/encoded buffers are
cleared after use. Browser/decoder internal copies are not claimed to be
fully zeroizable. Concurrent recognition is rejected as busy instead of
queueing more recordings or loading multiple composer models.

## Runtime and packaging

`faster-whisper>=1.2.1,<2` is now a backend dependency and part of the Windows
packaging import probe. Composer ASR defaults to multilingual Whisper Base,
CPU INT8, at most four threads. It has a separate model cache from remote
Whisper and does not change `GALAXYSSI_WHISPER_MODEL` or remote model profiles.
Set `GALAXYSSI_COMPOSER_WHISPER_MODEL` to another faster-whisper model name or
a local converted-model directory if required.

The first use loads the cached model, or downloads it to the standard
Hugging Face cache when absent. Models are not bundled in the application.
Cached models are opened offline first, avoiding network metadata checks.
Download/setup failure, unavailable runtime, microphone permission, absent or
busy microphone, silence and timeout have distinct user-facing messages.

## Validation

- `npm run check`: 88 tests plus the Desktop structure check passed.
- `pytest test_composer_stt.py test_stt_bridge.py test_remote_whisper_node.py -q`:
  23 tests passed, including the post-change rerun.
- `smoke-composer-voice.js`: synthetic Chinese speech passed through Electron
  getUserMedia, actual MediaRecorder Opus, IPC, authenticated HTTP and real
  faster-whisper. Both cold and warm runs produced text, returned to idle and
  stopped all microphone tracks. One measured warm run took 1.74 seconds after
  release; cold runs took 10-19 seconds. These are test-machine samples, not
  latency guarantees or a human microphone accuracy evaluation.
- The broad UI smoke rendered its screens but initially failed its Windows
  temporary-directory cleanup with EPERM; this is not counted as a full pass.
- Restarted the user's source-launched Desktop, visually confirmed version
  1.5.2 and the composer, and verified backend health was ready. Existing chat
  history and paired-device entries remained present. The authenticated API
  on that running backend transcribed the synthetic Chinese sentence in
  3.40 seconds cold and 2.22 seconds warm. No transcript was sent as a chat.

For a repeatable live pipeline check, provide a synthetic speech WAV file and
the backend Python executable, then run from `apps/desktop`:

```powershell
$env:GALAXYSSI_STT_TEST_WAV = 'C:\test-audio\speech.wav'
$env:GALAXYSSI_PYTHON = 'C:\runtime\python.exe'
node .electron-runtime/node_modules/electron/cli.js scripts/smoke-composer-voice.js
```

The test uses a separate Electron profile, an isolated loopback backend and a
fake microphone. It does not read or send real conversations or microphone
audio. Physical-microphone acceptance still requires speaking into the device.
