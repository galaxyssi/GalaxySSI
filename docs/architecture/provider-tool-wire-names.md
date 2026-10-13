# Provider tool names

HTTP native-tool adapters use deterministic transport names for OpenAI-compatible,
Anthropic and Gemini requests. Native dotted IDs remain unchanged in registry
contracts, planning manifests, encrypted journals, tool arguments and result
evidence. Decoding resolves the transport name against the catalog disclosed for
that request, then returns the original native ID and version for execution.

## Mapping

Dots become double underscores; native underscores become `_u`. Other native ID
characters are unchanged. This distinguishes dots from underscores without relying
on a lossy replacement. Encoded names longer than 64 characters use `gssi_h_`
followed by 56 SHA-256 hex characters. This prefix cannot occur in short escaped
names. Long IDs are hashed, not truncated. Every catalog checks for collisions
before encoding or decoding; it never chooses the first ambiguous match.

Exact canonical IDs are also accepted only when they identify an unambiguous tool
in the current request's catalog. Unknown names and unavailable tools do not gain
access through alias decoding. The same mapping applies to declarations, assistant
call history and Gemini function responses. Call IDs, argument values, evidence
and durable native identities are not rewritten. A native-ID footer in the HTTP
description lets models distinguish function names from IDs used by discovery
tools and planning arguments. It does not change the native contract fingerprint.

## Provider rules

The common transport subset is letters, digits, underscores and dashes, at most
64 characters. This is an interoperability choice, not a new native tool limit.
The existing protocol input bounds still apply.

- [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create):
  function names use that character subset with a 64-character maximum.
- [Anthropic tool definitions](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools):
  the documented tool-name pattern allows the same characters with a 128-character maximum.
- [Gemini generateContent](https://ai.google.dev/api/generate-content.md):
  declarations allow additional characters, while call/response name descriptions
  list the narrower subset; the adapter uses the common subset throughout.

These references were checked on 2026-10-13. Name validation alone does not prove
that an entire request satisfies every provider's model-specific API requirements.

## Verification

JVM coverage checks 1,000 generated native IDs for deterministic bounded names,
long-name distinction, alias/canonical collisions in either catalog order, response
normalization, undisclosed tools, unchanged evidence and historical serialization.
S20U tests use actual HTTP adapters and encrypted journals against scripted local
responses. The local server rejects invalid typed function-name fields, including
history and Gemini responses; it does not inspect arbitrary strings inside data.

Tests interrupt after a committed setup action, reopen the journal, refresh the
tool catalog and finish the original goal without repeating setup. A canonical-ID
journal created without HTTP encoding also resumes through the new transport.
These are framework and protocol tests. Autonomous diagnosis, login and recovery
with a real external model remain separate end-to-end acceptance requirements.
