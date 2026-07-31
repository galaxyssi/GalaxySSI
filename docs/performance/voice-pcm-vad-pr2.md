# Voice PCM Capture and Adaptive Endpointing

## Scope

This stage replaces the primary Android voice-command capture path with a shared 16 kHz mono PCM pipeline. It covers chat hold-to-talk, Agent input, and wake-page commands. The legacy AAC/M4A recorder remains behind `voice.audio_record_pcm_v1` for rollback and for unrelated media-capture tools.

Debug builds enable the PCM path by default. Release builds keep it disabled until device latency and recognition gates are accepted.

## Pipeline

```text
AudioRecord (PCM16, 20 ms)
  -> bounded pooled frame channel
  -> VoiceAudioHub
       -> adaptive speech VAD
       -> adaptive endpoint detector
       -> in-memory PCM ring buffer
       -> waveform level
       -> privacy-safe diagnostics
  -> transient PCM WAV adapter
  -> existing LocalWhisperAsr compatibility facade
```

`VOICE_RECOGNITION` is attempted first and `MIC` is the compatibility fallback. AEC and noise suppression are enabled only when Android reports support. AGC remains off by default because vendor implementations vary.

## Endpoint Policy

- No-speech timeout: 2.5 seconds.
- Short utterance tail: 850 ms.
- Normal utterance tail: 650 ms.
- Long utterance tail: 500 ms.
- Allowed tail range: 350-1,200 ms.
- Pre-roll: 300 ms.
- Post-roll: 200 ms.
- Maximum command duration: 60 seconds.

Hold-to-talk remains manually terminated, while still using VAD to preserve speech boundaries. Wake-page commands stop automatically. The model never decides when microphone capture ends.

## Reliability and Privacy

- The audio thread runs at Android audio priority and never performs ASR or file conversion.
- Frames come from a fixed object pool; a bounded queue drops stale frames instead of blocking microphone reads.
- PCM stays in a bounded in-memory ring and is cleared after finalization.
- The WAV bridge is transient and deleted by the existing ASR path after use.
- Permission denial fails before opening the microphone.
- Android audio-policy silencing, including call interruption, terminates capture with a structured failure.
- Bluetooth, wired, USB, and built-in input route changes are observed without reopening a second microphone.
- Moving the Activity to the background cancels active command capture.
- TTS completion is matched by utterance and trace ID, so a stale playback callback cannot terminate a newer capture or ASR session.
- Blank and unrelated trace IDs cannot claim the active voice coordinator session.
- Diagnostics contain only timings, counters, source type, and route class. They never contain PCM or transcript text.

## Compatibility and Rollback

Set `voice.audio_record_pcm_v1` to `false` to restore the previous MediaRecorder path. The existing ASR facade accepts the transient PCM WAV file directly, so provider routing and message behavior do not change in this stage.

## Validation

- Ring wrap, pre-roll, and post-roll unit tests.
- Adaptive VAD start/end unit tests.
- 350-1,200 ms endpoint and 2.5-second no-speech tests.
- WAV header and atomic-finalization tests.
- VoiceAudioHub single-stream fan-out and snapshot tests.
- Real-device AudioRecord instrumentation on Samsung SM-T575: 320-sample PCM frames and cancellation under one second.
