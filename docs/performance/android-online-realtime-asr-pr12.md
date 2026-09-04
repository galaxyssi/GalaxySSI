# Android Online Realtime ASR

This change introduces the replaceable online realtime ASR path behind
`voice.online_realtime_asr_v1`.

## Runtime contract

- The microphone still has one owner: `VoiceAudioHub`.
- PCM is captured as 16 kHz mono PCM16 in 20 ms frames.
- Network consumers receive immutable frame copies before pooled capture frames are released.
- The WebSocket transport aggregates contiguous frames into 60 ms batches and preserves capture sequence and monotonic timestamps.
- Audio and event queues are bounded. Overflow produces a structured fallback signal instead of unbounded memory growth.
- Provider events normalize to ready, speech start, partial, stable, final, usage, metrics, recoverable error, fatal error, and closed.
- A transcript ID may commit execution once. Accurate or manually edited text is a correction, never a second command submission.

## Credentials and privacy

The APK contains no provider key. A build may configure only a secure credential broker URL with:

```text
-Pgalaxyssi.realtimeAsrCredentialBrokerUrl=https://example.invalid/asr/session
```

The broker returns a short-lived in-memory credential and secure WebSocket endpoint. Credentials are redacted from diagnostics and cleared when the session closes.

Online audio is disabled until the user explicitly allows both online voice and microphone audio upload. Wi-Fi-only and provider-side deletion preferences are enforced before the provider is selected. Local private mode never opens the broker or network session.

## Failure behavior

- Failure before connection selects local ASR immediately.
- Failure during speech reuses the retained in-memory PCM when the buffer is complete.
- A reliable online final prevents duplicate local submission.
- A displayed partial without a final is replaced by the local final.
- An incomplete PCM buffer fails clearly instead of executing a truncated transcript.

Local Whisper remains the default when no broker is configured, online consent is absent, the network policy rejects the connection, or the realtime provider fails.
