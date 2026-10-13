# Durable native-model context handoff

Long tool loops can exhaust a provider window even after tool output compaction.
Signed assistant state cannot be shortened in place. A provider or credential
change can also make the old native call history invalid for the next model.

The cloud native adapter now separates its HTTP projection from the canonical
execution journal. At a fully observed tool boundary it can start a fresh model
context containing:

- The original system instructions and all user instructions, verbatim.
- A host policy identifying the context boundary, not a new user task.
- An explicitly untrusted evidence capsule with recent observed results, operation
  IDs, receipts, argument digests/excerpts and tentative assistant notes.
- Every result in the latest tool batch, live operation, uncertain effect and latest failure. Required evidence
  is never silently dropped to manufacture a successful continuation.

User-owned browser sessions retain their handoff IDs and durable wait identity.
Unknown outcomes retain their exact read-only recovery query and original operation
identity. These references are evidence, not instructions to resubmit a mutation.

The capsule labels omissions and never asserts goal completion. Web pages, tool
errors and assistant notes remain evidence rather than system authority. Provider
signatures and opaque reasoning are never copied into the provider-neutral capsule.

## Persistence and execution

The successful model response carries a host-created context checkpoint containing
the source message count/digest, route fingerprint and capsule. The existing
encrypted journal persists it atomically with that response. Later rounds and
reopened journals reconstruct the same prefix and append only the new signed tool
chain. The boundary is bound to its exact source history; moving it or changing
the original input is a recovery error.

Canonical tool calls, admission IDs, effect claims and committed receipts do not
change. A context handoff neither starts a new execution run nor authorizes replay
of completed effects. It cannot discard unanswered native calls. No extra model
request is made to generate the capsule; the active model decides the next action.

Normal small requests stay unchanged. Every cloud response also records a host
route digest, so unsigned responses retain origin information. Unknown legacy
tool histories conservatively become evidence rather than imported native calls.
Missing new fields leave legacy checkpoint bindings unchanged. The per-adapter
token-estimate cache releases entries from retired context projections.

## Limits and acceptance

This is a bounded structured evidence handoff, not a semantic summary of every
historical fact. Older omitted detail remains in the encrypted execution journal;
the model can use the [paged observation reader](model-observation-history.md)
in newly created native cloud/local loops, or inspect current state. Semantic
memory selection remains separate. If required user
instructions or required live/uncertain evidence alone exceed the model window,
the adapter reports the concrete context error instead of truncating requirements.
Tool-schema token accounting and provider-specific server compaction are separate
remaining work; this patch does not claim unlimited-context execution.

Regression coverage exercises window pressure, unsigned/legacy routes, provenance,
pending results, changed history, all user constraints, cache retention, committed
effect replay and encrypted restart through three strict local HTTP protocols.
These scripted tests do not establish real-model autonomous diagnosis or website
login acceptance.

## Sources

- [Anthropic context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Long-running agent harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Gemini signed tool turns](https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures)
