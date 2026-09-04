# Cloud Model Streaming

This change replaces the wait-for-complete cloud chat path with a cancellable, provider-neutral stream while retaining the complete-response path as a compatibility fallback.

## Runtime flow

1. The existing context compiler builds a budgeted conversation and preserves its summary contract.
2. `CloudConversationStreamEngine` prepares an OpenAI-compatible, Anthropic, or Gemini request.
3. `OkHttpCloudModelStreamClient` reuses the shared connection pool and normalizes provider events.
4. The first text delta is rendered immediately.
5. Later deltas are merged at an 80 ms UI cadence to avoid RecyclerView churn.
6. Usage and terminal events remain independent from text delivery.
7. The final message is persisted and published to the global conversation bus only after a real terminal event.

Each cloud contact has at most one ordinary response stream. A newer request cancels the older stream for that contact; streams for different contacts remain independent. Persistent Agent runs are not affected.

## Protocol guarantees

The normalized stream exposes connected, text delta, tool-call delta, usage, completed, and failed events. It enforces:

- monotonically increasing local sequence numbers;
- provider sequence de-duplication when a provider supplies sequence metadata;
- UTF-8-safe SSE and JSON-line parsing across arbitrary network chunks;
- cumulative and incremental tool-argument de-duplication;
- one execution per assembled tool-call identity;
- structured HTTP and provider errors;
- explicit cancellation reasons;
- no completed event after cancellation or an unterminated disconnect.

Tool arguments are fully assembled and parsed before the existing tool layer is invoked. The stream parser never executes a tool directly.

## Provider compatibility

The adapters cover:

- OpenAI-compatible Chat Completions and Responses events;
- Anthropic Messages text, tool, usage, and terminal events;
- Gemini text, function-call, usage, and terminal events.

Providers that reject streaming fall back to the existing complete-response API. A contact may also disable streaming explicitly. The legacy path now shares the same pooled OkHttp client instead of creating a new URL connection for every turn.

## Failure behavior

If a connection ends after partial output, GalaxySSI retains the partial message, marks it interrupted, and does not report a completed response. A retry is a new request with a new request ID, so old deltas cannot be appended to the new answer.

If no text arrived, the existing natural-language error surface is used. Provider error bodies are read before mapping, while low-level stacks and credentials remain hidden from the conversation.

## Metrics and feature flag

Streaming records model request start, connection, first delta, and completion timestamps. Token usage is attached when the provider emits it.

The implementation is controlled by `voice.cloud_model_stream_v1`. Debug builds enable it by default; release builds remain opt-in during staged rollout. Disabling the flag restores the previous complete-response behavior.

## Verification

MockWebServer and pure Kotlin tests cover:

- byte-level UTF-8 chunking and ordered character/word deltas;
- exact first-delta arrival timestamps;
- tool arguments split across frames;
- Anthropic empty initial tool input followed by partial JSON;
- duplicate and out-of-order provider sequences;
- usage arriving near stream completion;
- `[DONE]` and provider-specific terminal events;
- retryable 429 and 503 responses;
- connection interruption after partial output;
- active-request cancellation;
- complete JSON compatibility;
- OpenAI-compatible, Anthropic, and Gemini normalization;
- first-delta UI delivery and 80 ms coalescing.

Validated on 2026-08-01 with:

- 1,261 Android JVM tests: 0 failures, 0 errors, 1 intentional skip;
- 15 focused model-stream protocol and UI-merger tests;
- the repository and Android APK build gates;
- bundled Android runtime verification;
- debug APK install and launch smoke on a Samsung SM-T575 running Android 13.
