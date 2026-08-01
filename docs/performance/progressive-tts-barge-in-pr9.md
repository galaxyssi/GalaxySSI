# Progressive TTS and Barge-in

PR-9 replaces whole-response speech playback for streamed cloud-model voice replies with a request-scoped sentence and audio pipeline.

## Pipeline

```text
model text delta
  -> SentenceCommitter
  -> normalized speech chunk
  -> bounded TtsChunkScheduler
  -> Microsoft Edge short utterance or Android system TTS
  -> playback completion
```

Chat text remains unchanged. Speech normalization is a separate representation and removes private reasoning tags, code fences, inline code, JSON payloads, Markdown tables, raw URLs, long identifiers, and sensitive file paths.

`SentenceCommitter` supports Chinese and English boundaries, comma thresholds, a bounded first-chunk wait, provider sequence de-duplication, final flush, and incomplete structured-content protection. An unclosed code, JSON, URL, or Markdown fragment cannot be split in a way that exposes its remaining bytes as speech later.

## Playback isolation

Every chunk carries the model request ID and an increasing speech sequence. `TtsChunkScheduler` rejects stale sessions and out-of-order chunks. It keeps a bounded queue, coalesces a bounded tail during bursts, records underruns, and accepts late callbacks only when their generation and playback token still match.

Microsoft Edge TTS remains supported as a short-utterance provider with Android system TTS fallback. Edge synthesis, its WebSocket, MediaPlayer, and wait latch are now cancellable together. A stopped request cannot wait for the old 90-second playback timeout or start playing after a replacement session begins.

## Barge-in policy

Starting interactive voice input performs these operations synchronously:

1. stop current speech and clear queued chunks;
2. reject late audio from the old session;
3. cancel an ordinary cloud-model stream;
4. retain persistent remote Agent runs;
5. release playback audio focus;
6. allow the new microphone session to start.

The voice page also provides a conservative tap-to-interrupt fallback on its animation and reply panel. PCM capture already prefers the voice-recognition source and enables platform acoustic echo cancellation when available.

## Feature flags

- `voice.sentence_committer_v1`
- `voice.progressive_tts_v1`
- `voice.barge_in_v1`

They default on in debuggable builds and remain opt-in in release builds until latency and device metrics satisfy the rollout gate.

## Metrics

- `model_first_sentence_committed`
- `tts_request_started`
- `tts_connected`
- `tts_first_audio`
- `tts_playback_started`
- `tts_queue_underrun`
- `tts_barge_in_started`
- `tts_barge_in_completed`
- `tts_completed`

The diagnostics summary exposes `model_first_sentence_ms` and `tts_barge_in_ms`.

## Verification

Run the focused deterministic gate:

```bash
npm run smoke:android:voice-barge-in
```

The gate covers Chinese, English, mixed punctuation, timeout commit, Markdown, code, URL, JSON, duplicate deltas, flush behavior, bounded queue operation, underrun reporting, playback failure, cancellation, persistent-Agent retention, and late old-session callbacks.
