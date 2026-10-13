# Cloud planner catalog recovery

## Stable contracts and live readiness

New guarded cloud planning loops save an encrypted, scope-bound registered-tool
contract fingerprint before inference. The model loop's journal binding covers
that contract view, not a transient availability snapshot. Original messages,
planning revision, permissions, budget and provider selection retain their
existing recovery bindings. Installing dependencies does not create a new goal.

The HTTP adapter discloses only the currently available subset of that original
view. It freezes one snapshot for each HTTP request and its response decoder.
Provider catalog encoding uses the actual disclosed subset's fingerprint, not
the durable contract fingerprint, so an old cached JSON catalog cannot conceal
a repaired capability. OpenAI-compatible, Anthropic and Gemini adapters share
this path. The existing static-catalog adapter API remains unchanged.

Readiness refresh is event-driven: a new mutation result or explicit capability
inspection invalidates the registry's availability cache. Repeated model rounds
and read-only results retain the normal cache; there is no new polling loop or
fixed delay before a newly installed capability can be disclosed. The model
chooses diagnostics, installation, alternatives and final verification. The
host does not infer repairs from goal keywords.

## Recovery integrity

Contract, version, schema, permission, risk or registered-view changes are not
treated as readiness changes. Recovery rejects a different contract before
another model request; another conversation/turn/task cannot reuse the provider
catalog session. Runtime tool invocation still checks actual availability and
authorization. A catalog binding is not an Android permission grant.

Legacy available-only journals retain their exact old catalog. They are not
silently promoted because they contain no proof of the original unavailable
contracts. Corrupt bindings do not fall back to a different executable plan.
A prepared catalog binding also prevents deterministic fallback before the first
model response, preserving the original durable planning intent.

## Verification boundary

Pure tests cover stable readiness recovery, real contract drift, legacy behavior,
scope isolation, provider encoding cache separation, refresh cost and committed
installation replay. Android tests reopen encrypted production journals and use
the actual HTTP model adapter against local scripted Provider responses for
all three protocol families. A fixed registry clock verifies same-process setup
repair without waiting for availability-cache expiry.

These are production-path framework tests, not real-provider reasoning evidence.
They do not prove autonomous website login, successful browser dependency
installation or diagnosis of unspecified real-world obstacles. Those broader
end-to-end acceptance requirements remain open.

## HTTP transport names

The original catalog-recovery increment emitted dotted native IDs as HTTP
function names. [Provider tool-name mapping](provider-tool-wire-names.md) now
converts declarations, historical calls and responses consistently while retaining
native journal identities. Local HTTP recovery fixtures reject invalid function
names. This closes the known naming defect; real-provider autonomy and complete
model-specific request compatibility still require end-to-end verification.
