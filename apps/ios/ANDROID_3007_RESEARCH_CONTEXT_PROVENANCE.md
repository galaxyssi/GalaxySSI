# Research Context Source Follow-up

Actual incremental baseline: main 0bdfc81662cc27f638f0b3360f13c399ad2ba704 after #4570 merged during implementation. The PR contains only this context-source increment, not the already merged source-membership or actor/worker changes. iOS only.

## Implemented

- Realtime cognition items preserve declared primary/metadata sources plus recorded cognition context IDs. Research and autonomous items retain complete recorded source sets AND their primary ID. Any excluded member removes the whole item; long-horizon goals no longer subtract an excluded member and present the remaining set as the source of the original text. SESSION_PRIVATE cognition is excluded even for unscoped projection.
- Scoped provider reads reject legacy research/autonomous records missing source sets. Unscoped string reads preserve their legacy display compatibility, not authorization. Cached snapshots reapply current exclusion/allowlists to full sets before relevance/selection, without rewriting original provenance or refreshing on every read. Aggregate continuity counts remain the existing source-less runtime-status item, not conversation prose.
- Synchronous research context uses the existing selected-item projection API. Its optional conversationIds records selected item sources plus the direct conversation history source when history text is actually included. This is NOT every known/allowed conversation. It can conservatively include a selected item omitted later by character bounds.
- Evidence and synthesis dispatch records gain optional contextConversationIds, encoded as context_conversation_ids. Existing JSON without the optional field remains readable but lacks authorization proof. New public-attention requests record an empty set and retain their existing empty private context.
- The existing exact-saved-request/owner gates now additionally require present context metadata and current source containment before backend dispatch, local/cloud callbacks and result consumption. Public-attention requests must carry an empty context set. No fallback that infers missing proof from current settings; legacy requests remain subject to existing lease/retry recovery, not automatic metadata backfill.
- After an accepted non-public response, union its recorded context sources into the persisted research task before saving any result/proactive state. Later evidence/synthesis and context projections then retain those accepted dependencies. When autonomous research completes, union its complete source set into the existing run's optional set; nil remains nil, never fabricated proof.
- Preserve prompt text builders, transport payloads, selection scores/caps, renderer limits, model budgets, resource policy and underlying result evaluation outside the declared source hooks. Existing services use their already-installed boundary gates; no new wire payload fields, downloads, permissions or OS background grants.

## Evidence

- Ten new XCTest methods authored SOURCE ONLY: six context fixtures for complete unions, mixed excluded sources, private sensitivity, scoped-vs-unscoped legacy behavior, warm-cache revocation and selected-vs-all-allowed sources; four research fixtures for optional JSON/legacy metadata, request scope/public isolation, both dispatch stages and equality binding.
- Fixtures are NOT executed. They do not exercise Store/Coordinator consumption, callback races, actual persistence/restart, live source privacy changes during model work or real synthesis acceptance. Result-to-task/run retention is checked at source wiring, not native fault/concurrency acceptance.
- All six dedicated source guards passed, comparing complete production files outside declared hooks and composing prior foreground/cognition/research/autonomous/gap contracts. `npm run check:ios`, all six checker JS syntax checks and `git diff --check` passed. None are Swift compilation or native/runtime acceptance.

## Remaining

- These are host-maintained declared source/context IDs, not cryptographic origin proof for arbitrary historical/model/attachment/tool/imported prose. Missing legacy task/run/dispatch metadata stays untrusted; no migration/re-enqueue UI or reconstruction from today's sessions.
- Unscoped legacy projection is compatibility only. Do not use it as an authorization boundary. Scoped callers must continue passing current allowed sets; direct policy helpers retain caller-controlled compatibility defaults.
- No atomic source/session/task transaction, cross-process/shared-file CAS, callback cancellation or retraction of sent/queued prompts and already-running model/network/tool effects. Privacy can change after a boundary snapshot. Proactive delivery, other native-tool/attachment/lifecycle provenance and historical records still need audit.
- Task/run source unions are conservative and can grow with accepted evidence. No source-dropping optimization or per-token disk recheck is added. No measured performance, renderer/device, crypto/storage, restart or privacy acceptance.
- No native build/typecheck, XCTest execution, CI watching or IPA. Android #3007 and the full Android PR backlog are NOT complete.
