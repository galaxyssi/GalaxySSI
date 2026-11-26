# Android #3007 Retained Context Follow-up

Base: main 5f6297c3cf8348fa777e5c80cdee5f46cf7c10a1, synchronized after #4564 merged; initial branch base was 3fed6016e. Correct an iOS integration gap exposed while auditing the retained context/prewarm work merged in #4552. This is a remaining-context-path correction, not a claim Android #3007 introduced a new privacy protocol. Existing Android pinned reference remains 65655f0c79c6ab04121150229a65b089180f82f2.

## Actual Gaps

- The compiled planning/voice bridge checked globalAgentSettings.enabled and current eligible conversations. The separate foreground model-planning path directly read the retained provider without checking that switch and lacked the allowlist. It also used an opaque conversationOverride.globalContext string as its realtime input, so old text could bypass current membership changes.
- Long-horizon goal projection subtracts excluded conversation IDs before constructing an item. Checking only the projected item's remaining IDs therefore does not prove ALL original sources were eligible. A mixed private/allowed goal could retain its title after its private ID was removed.

## Implementation

- GlobalRealtimePlanningScope captures current known non-private/non-paused IDs and exclusions once per use. Disabled or explicitly suppressed calls evaluate neither the conversations getter nor the retained provider getter. This prevents a disabled direct path from reading the cache or scheduling a refresh. The ordinary compiled bridge reuses this same scope with its original 10-item/2,000-character bounds and keeps its disabled core-memory return unchanged.
- The foreground direct/replanning field uses that live scope and NEVER copies the override's old global string as realtime state. Rebuild nonempty override globalContext through the existing compiled bridge with the current request/turn and settings. Selected-provider-only mode and explicitly blank overrides remain suppressed; do not add global context where the caller deliberately supplied none. Independent core memory, histories, summaries, task ownership, permission/disclosure and dispatch policy remain unchanged. History/summary override freshness is not newly established by this correction.
- Before projecting long-horizon goals, require their ORIGINAL sourceConversationIds to be a subset of current eligible IDs when an allowlist is supplied. Do not allow excluded-source subtraction to erase provenance. Keep the existing projected-item filter, redaction, ranking, time/bounds policy, retained snapshot generation/TTL and synchronous no-allowlist build contract. Empty/global source sets retain their prior behavior. This does not establish the provenance of empty/global records or backing-store per-profile isolation.
- Nine XCTest methods authored, SOURCE ONLY, NOT executed: lazy disabled/suppressed gates; blank/selected-provider suppression; one-snapshot membership; live private/paused/deleted cache filtering; mixed/global IDs; disabled warm cache/no refresh/reenable; original mixed-goal privacy provenance; formatter bound forwarding. Full Coordinator override rebuilding and actual model submission remain source-wiring evidence, not executed end-to-end tests.

## Limits

Dedicated live-planning-context source guard, npm run check:ios, checker JavaScript syntax and git diff --check passed against this base. The guard compares the complete services/runtime/provider files after only declared foreground-context/source-set hooks and freezes core/history/model/dispatch dependencies. This is not a claim that every historical whole-file guard matches the current main or that any native fixture executed.

The scope is rebuilt on the current foreground call, not an atomic revocation of already emitted prompts or already running provider/source I/O. Background cognition/research synchronous provider calls, their archived global provenance, history override validation and other #3007 dispatch/cache/media/startup/transport gaps remain separate work. Do not label all global privacy or all Android parity complete.

No native build/typecheck, XCTest execution, CI watching, model/privacy/concurrency/device acceptance or IPA. Source/project checks cannot prove native runtime correctness. Existing history/index/model and dependency code is frozen against the actual main base outside explicitly declared foreground-context hooks.
