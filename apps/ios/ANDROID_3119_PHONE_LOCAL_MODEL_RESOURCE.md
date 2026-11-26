# Android #3119: Phone Local-Model Resource Identity

Follow-up correction to the existing iOS routing/queued-producer adaptation,
not a new native inference implementation or completion of Android #3119.
Baseline: main `104e4e156ed187a8e5980813efc901bb08d2bd34`, synchronized
after scored-context PR #4590 merged. Its routing changes are retained, not part
of this increment's diff against main.

## Actual Failure Path

AgentCallableTargetCatalog builds the phone's installed local model as reserved
target local-llm with adapter ios-local-model and localInference capability.
AgentResourceCatalog nevertheless classified that target as remoteLocalModel,
whose location is trustedDesktop. The queued native producer independently builds
that catalog and evaluates networkRequired from its resource location. As a
result, a valid local inference request could fail offline/network/connector or
private-policy checks before reaching the already implemented local generator.
The generic inferred provider profile also described a network-local/cloud-like
service rather than the actual phone executor.

## Correction

Recognize only the reserved ID, model kind, exact iOS adapter and native inference
capability together. An explicit existing profile must also agree on resource
identity, local-model kind, phone location and adapter. A remote Ollama/local-
inference target, a prefixed remote ID, a display name or a mismatched supplied
profile does not become a phone resource.

The real local-target builder now supplies a phone ProviderProfile with the exact
selected model ID and configured context capped by that model's maximum. Preserve
its original readiness callback/status; an unready model remains needsSetup and
cannot dispatch. The native profile reports phone-system trust, no paid provider
cost and no network endpoint/API-key requirement. Resource classification is
onDeviceModel, so the unchanged queued producer and admission policy use their
existing phone branch rather than demanding a network connection.

Keep the original two-run capacity, provider/product identity and runtime failure
domain key. Existing local leases/health scope cannot be bypassed by renaming the
runtime. No output-token ceiling is invented (zero means unspecified), and no
background or streaming capability is newly advertised. The generator's actual
limits, permissions, enabled-profile/readiness checks, cancellation, response
journals, session/profile ownership and disclosure rules are unchanged.

This is metadata classification for a trusted in-app catalog producer, not a new
authorization token for remote payloads or a new model installation path. Existing
explicit profiles remain unchanged. Remote local-model resources retain their
network boundary. No weights, runtime packaging, download, version or IPA changes.

## Verification Limits

Eight Swift fixture methods authored/registered, NOT compiled/executed: actual
ready/unready target construction; phone catalog/profile/model/context binding;
offline/private admission and the queued producer's budget expression; remote
same-name/adapter/capability/profile negatives; stable runtime key/capacity; and
profile round-trip with unspecified output limit.

The source guard compares the complete resource/profile implementations after
only the exact local constructor, native classifier and new profile hooks. It
freezes the full Coordinator, budget/run-slot policy, inference runtime/settings,
resource scoring, disclosure and transport. No native typecheck/build/XCTest,
actual offline/private generation, model loading, runtime-concurrency/device
acceptance, CI monitoring or IPA is included.

Checkpoint: seventeen related JS source-scope guards passed after synchronizing
main's scored-routing integration. iOS project structure, changed iOS literal-
Han and diff whitespace checks passed. These are not an all-repository or native
test pass.

This fixes the phone resource identity used by these existing call paths, not
generic timeout/deferred observation, all routing/attachment entry points or the
overall Android-to-iOS backlog.
