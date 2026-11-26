# Android #3119: Scored Main-Service Routing Context

Reference: Android #3119 merge `e7c6af6ef3eed21c7fb697b4458d1cf742833dc4`,
AgentResourceRouter.kt SHA256
`d95d5d072eb0637ee20e0a883559918979bf0be48daf4dfb9021fbbcfb37663f`.
iOS baseline: main `9781cd99a1ad53c7408a664f1a3b4ebb27579f3e`.
The source guard also pins that baseline's current Android task-budget policy,
which explicitly treats resource counters as telemetry, not termination limits.
Do not restore the older numeric token/cost/memory admission restrictions.

## Live Integration

Main-service Auto selection, dispatch-time route refresh and fresh connector
fallback now share scoredAutomaticConnectorRoute. Capture one visible callable
catalog, exact runtime registrations/capacity, read-only adapter health, current
scoped reported usage, pairing state, network probe, task budget and connector
permission. Feed an explicit AgentRoutingDecision to the existing selector,
rather than nil and an implicitly reconstructed default-budget decision.

AgentAutomaticRoutingContext is an in-memory value, not a new store or transport
contract. Existing admission runs before scoring: enforce exact registration,
capacity, privacy/mandatory capabilities, current network/cloud/paid-provider
settings and current health. Reject device-only/non-reasoning targets. A complete
catalog remains informational; only admitted primary/fallback IDs are selectable.
An empty admitted set yields an explicit no-route decision, never a new catalog
candidate. Preferred IDs do not bypass admission.

For scoring, project only exact-registration location, trust, cost, latency,
capabilities, capacity, failure domain and provider profile onto that candidate.
This keeps the scoring description consistent with the admission source, notably
the phone location of the real local model. Never borrow another installation's
registration through a product/family alias. Runtime registrations are still
produced by the existing callable-target/run-slot path; this does not add generic
registry discovery or grant capabilities to a different execution target.

A healthy admitted displayed primary gets a single-candidate scored decision
with stable_auto_primary. The selector recognizes this exact-primary/empty-
fallback decision and returns before calibration or shadow observation. Other
admitted targets are not scored by this branch. The legacy nil-decision fast path
is retained for existing callers. A marker on an excluded/foreign target cannot
override the selector's original admitted-ID/capability/health boundary.

Without that stable primary, score every admitted candidate using the existing
provider-resource scorer and actual health/usage snapshots. Keep the complete
candidate set until the existing selector performs self-calibration, domain-tier
fallback ordering, six-fallback bounds and optional quality promotion. This does
not introduce a new score formula, early seven-candidate cutoff or extra shadow
write. Fallback selection requests a fresh context without a remembered preferred
ID and retains existing attempt/deferred/failure-domain guards.

Manual selection, consent/disclosure, run slots, task/session bindings, replay,
transport, timeout and outcome/effect journals remain unchanged. Existing
recoverable-disconnected behavior is retained rather than manufacturing failures
from missing heartbeats. Environment capture preserves the existing validated-
network rule; unmeasured power/memory fields remain defaults, not invented probes.
Counters remain telemetry under the current budget policy. No cost estimate is
presented as a reported provider bill.

## Verification Limits

Eight Swift fixture methods authored and registered, NOT compiled/executed:
stable context/selector retention, full-primary rejection, explicit policy gates,
offline local reasoning, all candidates retained before calibration, explicit
no-route/catalog/device isolation, exact-registration/health evidence and no
restoration of removed numeric hard limits. These are not live Coordinator,
concurrent capacity, fault, privacy, provider or routing acceptance tests.

The source guard derives the three call-site changes from their old methods,
freezes the surrounding service and selector after precise fast-path hooks,
pins Android reference/current-budget bytes, and retains existing ranking,
calibration, health, usage, budget and transport implementations. No native
build/typecheck/XCTest, CI watching or IPA is included.

This connects scored admission/context to these main-service paths, not every
rule-planner/global/scheduled entry point. Generic active pre-timeout observation,
deferred discovery and broader dispatch/recovery acceptance remain incomplete.
Android #3119 and the full Android-to-iOS backlog are not claimed finished.
