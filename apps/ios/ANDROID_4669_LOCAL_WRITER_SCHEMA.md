# Local Team Writer Schema (Android #4669)

Reference: Android PR #4669, head `9cab75e19de460f75e7c83a82033acc02b4dd288`.
Scope baseline: main `14acae50dbb4a0ef3cef1e8332ed3c82e3c89c05`.

## Production Path

Each running conversational team job creates a fresh writer-format session. The existing
planner request may observe its successful HTTP response's URL and Server product.
The observation is consumed only after inference completes without tool calls and the
plan passes the existing strict decoder. This adds no probe or model call.

Only matching canonical numeric-loopback chat-completion endpoints advertising exactly
`llama.cpp` or `llama.cpp/<version>` (case-insensitive) establish capability. Any HTTP
redirect disqualifies observation, including a redirect back to the original endpoint.
Missing or invalid observations cannot establish capability. Invalid explicit observations
clear it. The iOS product parser additionally rejects product strings above 128 UTF-8 bytes.

The exact prediction writer and only synthesis/rewrite stages may use the capability.
The schema requires seven string fields, with only the two direction fields constrained
to `higher` / `lower`. Synthesis also allows an ordinary answer object; rewrite does not.
The host renderer, independent reviewer, one-handback budget, cancellation, uncertain-job
recovery, route/auth checks and local GGUF path remain unchanged.

Shared HTTP observation defaults off, excludes private reasoning continuations and
single-HTTP trials, retains normal redirects, and exposes only a request-ID-matched
single in-memory advertisement. Starting a new request clears old metadata. No headers,
capabilities, or private request data are persisted or added to transcript events.

## Verification

`node apps/ios/tools/check-team-writer-schema.cjs` checks integration gates, the pinned
Android field contract, exact shared-transport delta, unchanged engine/store/parser
boundaries, and Xcode source registration. Six synthetic XCTest methods cover the
capability, address, product, schema, request-preservation and redirect boundaries.

XCTest source is authored but not executed. No Swift/native build, live decoder/device
test, full repository check, CI monitoring or IPA packaging is performed for this change.
Static checks do not establish runtime decoder compatibility or scientific validity.
