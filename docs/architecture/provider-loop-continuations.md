# Provider continuation state

Native model loops preserve provider-owned assistant state when it is required
for the next tool round: Gemini signed content parts, Anthropic thinking and
redacted-thinking blocks, and OpenAI-compatible reasoning_content extensions.
The original content order, call IDs, arguments and signatures return to the
same provider unchanged. Gemini thought-only text is excluded from visible
assistant output. Opaque state has a redacted string representation and uses
the existing encrypted model-loop journal rather than a separate plaintext cache.

The continuation is bound to the assistant text and native calls. Admission may
assign a unique internal ID to a rejected duplicate; HTTP history and its tool
result still reference the original provider ID. This preserves protocol state
without executing rejected operations. Gemini calls without a provider ID keep
that omission in their signed history and response; synthetic IDs remain internal.

Cloud adapters snapshot their configuration and bind continuations to the provider,
endpoint, model and credential fingerprint. Journals store only the combined digest,
never the API credential. A different route or credential receives ordinary native
history without the source provider's opaque state. This prevents cross-provider
or cross-account disclosure; it does not claim that every provider accepts imported
tool history without a new context. Rotating a key for the same account also starts
without old opaque state because the client cannot establish account equivalence.

Checkpoints omit the new field when it is absent, preserving legacy binding
hashes. Existing journals cannot recover signatures that an older version already
discarded. Current signed tool chains survive context compaction, and retained
assistant blocks are never shortened or rewritten. Opaque payload size counts
toward token estimates. Tool observations can still be compacted. Required state
that exceeds a model window is not silently truncated; long-task context rollover
remains a separate concern.

Gemini's native HTTP adapter now sends the configured model through its endpoint,
without the unsupported top-level model field used by other protocol families.

## Sources and verification

- [Gemini thought signatures](https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures)
- [Anthropic thinking](https://platform.claude.com/docs/en/build-with-claude/thinking)
- [DeepSeek thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/)
- [Gemini REST request shape](https://ai.google.dev/api/generate-content)

Tests cover all three protocol families, parallel signatures, absent wire IDs,
duplicate-call rejection, restart replay, context pressure, modified history and
route and credential isolation. Android tests reopen encrypted journals and use strict scripted
HTTP responses that require continuation state in subsequent requests. These are
protocol/framework tests, not real-model website-login or autonomous diagnosis
acceptance.
