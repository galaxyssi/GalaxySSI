# Structured local file actions and read revisions

Local candidate implementation requests schema-constrained JSON using the
loopback chat-completions provider's `response_format` field. The contract has
four action shapes: list, read, write and finish. Goal decomposition and ordinary
chat requests are unchanged. Host file checks remain authoritative even if a
provider ignores the requested output schema. Unsupported schema requests report
the actual local-provider error; there is no silent cloud fallback.

The model no longer needs to reproduce a 64-character SHA-256 to modify an
existing file. A successful read returns a short `read_revision`. The next write
supplies it as `expected_revision`, together with the path and replacement text.
The tool resolves the receipt to the original path and SHA-256 and rechecks the
current bytes before writing. A receipt is not authorization to skip source scope,
link checks, content validation, independent host gates, or review.

Receipts are scoped to one tool instance, have a random instance prefix, and use a
128-entry LRU cache. They retain path/digest metadata, not source plaintext.
Repeated pages of the same file revision reuse a receipt. Eviction or process
restart requires rereading; it does not impose a total action or task budget.
Null `expected_revision` is accepted only when the target does not exist.
An unknown receipt, another file's receipt, or a receipt for changed content
produces a typed observation for the model. Receipt and legacy digest arguments
cannot be mixed in the same write.

The low-level file helper retains explicit digest writes for callers that already
use that contract. The local model action schema and prompt use receipts only,
and SHA-256 fields are removed from its file-result observations. Neither receipt
metadata nor file text is included in the content-free durable tool projection.

This improves action transport, not model competence. Structured output does not
guarantee that the model chooses the right action or preserves the intended file
contents. Real retained-workspace acceptance must still demonstrate successful
read, edit, host validation and publication. No host-generated candidate edits
are used to replace the model's work.

The existing local validation runtime is llama.cpp b10839. Its documented
chat-completions endpoint supports schema-constrained `response_format`:
https://github.com/ggml-org/llama.cpp/blob/b10839/tools/server/README.md#post-v1chatcompletions-openai-compatible-chat-completions-api

## Retained-workspace acceptance, 2026-09-08

The real Qwen3 1.7B Q8 local-provider campaign resumed its retained replacement
child at attempt 3. It listed files, received `read_revision_unknown` for an
invented receipt, then successfully read and wrote using the actual receipt.
The host prepared candidate `5b3ea9cbcba7f14e446122dbe253b9a6c3dd3b4b`.
No host-authored file edit replaced the model's work.

Semantic acceptance **failed**: the model replaced an existing document with a
short checklist rather than preserving its text and appending the requested
section. Static gates passed, while model-based review was disabled by the
existing policy. The candidate was not published. This is evidence that the file
action protocol can recover, not proof that the autonomous task was completed.
The incorrect candidate, worktree and audit observations were retained to test
independent goal/acceptance/diff verification and repair feedback next.
