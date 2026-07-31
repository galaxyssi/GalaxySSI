# Voice Interaction Coordinator (PR-1)

## Scope

PR-1 introduces a single event-driven coordinator for Android voice interactions while preserving the existing capture, ASR, routing, model, Agent, and TTS implementations.

The new coordinator owns only orchestration state. It does not decode audio, access model files, call JNI, parse network protocols, control media players, or fabricate remote Agent progress.

## State model

The coordinator uses the following lifecycle:

```text
IDLE
-> PREPARING
-> LISTENING
-> ENDPOINTING
-> FINALIZING_ASR
-> ROUTING
-> EXECUTING_LOCAL_ACTION | WAITING_MODEL_FIRST_TOKEN | STARTING_AGENT
-> STREAMING_MODEL_TEXT | AGENT_RUNNING | PLAYING_TTS
-> COMPLETED | CANCELLED | FAILED
```

Each transition carries a session ID, a monotonic revision, and monotonic timestamps. User content is held only in memory as part of the active interaction state and is not added to latency diagnostics.

## Compatibility bridge

`MainActivity` now publishes real lifecycle events from the existing implementations:

- `MediaRecorder` publishes preparation, speech start, speech end, and ASR finalization;
- local Whisper publishes one final transcript command;
- local tools, cloud models, and remote Agents publish their actual route and execution events;
- Android and Microsoft TTS publish playback start;
- existing completion, cancellation, and failure paths terminate the coordinator session.

The final transcript command has a stable idempotency key. Repeated ASR finals and Activity observer reattachment cannot dispatch the same user request twice. A correction may update transcript state after completion, but it never re-enters routing.

Late callbacks are accepted only when their session ID matches the current session. A delayed callback from a completed voice interaction cannot terminate or mutate a newer interaction.

## Activity recreation

The coordinator lives in an application-level registry rather than the Activity instance. A recreated Activity subscribes to the current snapshot without replaying commands. Removing and reattaching UI observers does not restart recording, ASR, routing, or Agent execution.

The legacy Android components retain their existing lifecycle behavior in this phase. Moving capture and decoding ownership outside the Activity is part of the subsequent audio/runtime phases.

## Feature flag and rollback

Android preference:

```text
voice.coordinator_v1
```

The flag defaults to enabled for debuggable builds and disabled for release builds. When disabled, coordinator helpers are no-ops and ASR final handling returns directly to the existing path. This preserves the pre-PR-1 behavior without requiring a binary rollback.

## Verification

The coordinator unit suite covers:

- canonical local-action transitions;
- exactly-once final transcript routing;
- correction without repeated execution;
- real remote Agent accepted/progress transitions;
- terminal cancellation and one legacy cancellation command;
- Activity recreation without restart;
- observer reattachment without command replay;
- observer failure isolation;
- late event rejection across sessions;
- wrong-session event rejection.

Repository voice smoke tests continue to exercise the existing voice reply, settings, and Desktop STT paths. PR-1 intentionally makes no latency improvement claim; it creates the lifecycle boundary required by later PCM, streaming ASR, streaming model, and streaming TTS phases.
