# Required Final Review and Local Plan Wire (Android #4649)

Baseline: Android PR #4649, merge `2ec1d7d3353c46443303612f895ffce33ef953f5`.
This increment was developed independently of the cloud-invitation and public-
objection PRs. Merging their main updates preserves both alongside this change.
Later model-authored final-editor behavior is separate.

## Explicit Final Review

English/Chinese final-answer audit requests are recognized after removing quoted
evidence and excluding negation and explanatory questions. They set a bounded
`final_review_required` flag on the planning payload. If the validated plan lacks
an independent final editor, execution stops after the single planning call,
before any worker or synthesis. The app publishes a localized missing-reviewer
notice, not a draft. It does not invent assignments, retry, vote or change provider.

## Canonical Loopback JSON Plans

Only the exact team planner prompt and canonical numeric loopback OpenAI route
may use the compact JSON plan wire. Hosts are literal 127.0.0.1 or IPv6 loopback,
path exactly `/v1/chat/completions`; userinfo, query, fragment, alias host, encoded
path, invalid port and trailing separators are rejected. Remote requests and
on-device GGUF inference retain their existing planning protocol.

Ordinary loopback OpenAI mode asks for JSON without assuming server schema
support. Complete, already-valid legacy line plans are still accepted, never
repaired or extracted from mixed prose. Strict mode accepts only complete typed
JSON and sends a bounded, tool-free JSON schema.

iOS represents the explicit strict opt-in as a `Custom` preset named
`llama.cpp (JSON Schema)` and a per-model optional setting, while retaining the
existing OpenAI API style. This avoids changing unrelated health/glasses/cloud
protocol switches. The model setting is saved through normal onboarding, is
valid only on a canonical loopback endpoint, and is preserved by Codable.
Absent/false settings retain old goal-route fingerprints; true participates in
the fingerprint so an approval cannot silently change decoding mode.

Foundation performs typed decoding. A narrow bounded lexical preflight first
rejects duplicate or escaped duplicate keys and noncanonical parent-number
lexemes that Foundation would otherwise normalize. It enforces depth, node,
container and string bounds. Exact role/root fields, kind, canonical earlier
numeric parents, one-line 400-character tasks/briefs, control/format characters,
role limits, fan-in/out and cycles are then validated with the existing parser
and graph validator before dispatch. No prose/fence/partial-result repair exists.

The isolated transport discloses the actual substituted system prompt, attaches
a schema only for strict opt-in and decodes the complete result before returning
to the engine. Default local-server requests have no schema requirement. Role,
call, parallelism, consent and cancellation limits are unchanged.

## Verification Boundary

Thirteen synthetic XCTest methods are authored for endpoint/system selection,
soft/strict compatibility, schema shape, graph order and boundaries, duplicate
keys, number coercion, malformed fields, control characters, one-call missing
review stops, legacy model configuration and route identity. They are not run.
Focused JS source contracts and the iOS project structure check are used.

No Swift/native compilation, native test execution, simulator/device run, local
server/model acceptance, paid call, scientific validation, full repository check,
CI monitoring or IPA generation is claimed. Android's model/device acceptance
results are not iOS evidence; in particular no molecular feasibility is asserted.
