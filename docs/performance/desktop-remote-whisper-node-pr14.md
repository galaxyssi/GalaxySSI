# Desktop Remote Whisper Node

PR-14 adds an optional high-accuracy Whisper correction path between a paired Android device and GalaxySSI Desktop.

## Execution contract

- Android keeps the fast transcript and the frozen PCM snapshot.
- A remote pass runs only after the user enables remote accuracy review.
- The selected Desktop must advertise protocol `galaxyssi.remote-whisper/1.0`, an active model profile, and a profile SHA-256.
- Android sends an encrypted manifest followed by bounded PCM chunks over the existing GalaxySSI Link session.
- Every chunk has a SHA-256 and the complete PCM has a second SHA-256.
- Desktop starts Whisper only after every chunk, route identity, client identity, consent record, length, duration, model profile, and hash is valid.
- The result returns through the existing transcript Correction pipeline. It never creates another command, model call, tool call, or Agent run.

## Privacy and failure behavior

- Only a cryptographically paired device can address the node.
- Remote voice consent is independent from Desktop Executor access and is disabled by default on Android.
- Incomplete, expired, interrupted, mismatched, or corrupted transfers never reach Whisper.
- Temporary WAV data is overwritten and removed after success, cancellation, or failure. The response reports whether cleanup was verified.
- Raw PCM and transcript content are excluded from Desktop logs and capability state.
- A cancelled or timed-out request cannot publish a transcript.
- Request IDs are idempotent. Replays return the cached result; reuse with different audio fails closed.

## Desktop configuration

The node uses the existing `faster-whisper` runtime. Supported remote profiles are `medium`, `large-v3`, and `large-v3-turbo`.

Environment controls:

- `GALAXYSSI_REMOTE_WHISPER_ENABLED=0|1`
- `GALAXYSSI_REMOTE_WHISPER_PROFILE=medium|large-v3|large-v3-turbo`
- `GALAXYSSI_REMOTE_WHISPER_MAX_PCM_BYTES=<bytes>`
- `GALAXYSSI_REMOTE_WHISPER_WORKERS=1|2`
- `GALAXYSSI_REMOTE_WHISPER_TEMP=<private temporary directory>`

## Focused verification

- deterministic model profile identity and one-model cache
- paired-device and explicit-consent rejection
- per-chunk and whole-audio integrity rejection
- out-of-order reassembly and incomplete-transfer expiry
- idempotent duplicate handling
- cancellation without transcript publication
- Android request packetization, response binding, timeout cancellation, and exactly-once completion
