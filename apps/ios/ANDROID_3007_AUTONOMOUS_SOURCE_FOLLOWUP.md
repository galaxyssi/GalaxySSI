# Autonomous Source Membership Follow-up

Baseline: main ca36efb28c5e2e72c620e20c4e88ccfe30e1549a after research #4567 merged during implementation. This PR contains only the autonomous increment, not the previously merged foreground/cognition/research diffs. iOS only.

## Implemented

- Extract the existing cognition primary/metadata source parser into GlobalBackgroundCognitionScope.sourceConversationIds without changing its sensitivity, invalidation or synthetic-goal rules. Cognition authorization still applies the same live allowlist after parsing.
- New autonomous plans require completed cognition, non-private/non-invalidated source metadata and recorded selected-context IDs. Save the union in optional sourceConversationIds. Keep synthetic goal identifiers out of actual history IDs. Existing runs are reused only when event identity and recorded source set match; no retroactive proof repair.
- Codable adds an optional camelCase run field: absent legacy fields remain readable but untrusted. Current known non-private/non-paused conversation membership gates autonomous claims, including plan reviews. Denied records are not lease-recovered or newly reserved; eligible records behind them can still run. Existing policy callers retain the default predicate.
- Stop before modifying an unreadable deliberation store. Do not return a claimed task or newly planned run when persistence reports failure. Existing instance locks and storage format remain unchanged.
- Before backend dispatch, recheck the live stored run, current sources, positive attempt correlation, current action/review owner and conversation/turn scope. Check local resource identity, paired trust/permission or cloud permission without silently choosing another resource. Reuse the existing local callback hook and gate cloud success/failure publication; stream flags remain cheap, not per-token store loads.
- Model response consumption requires a unique matching stored run, current source membership, current resource authorization and positive owner correlation before budget accounting or parsing. Nonblank conversation/turn/task fields must match; blank legacy scope remains supported, not cryptographic authentication. Action/review resource IDs must match the response contact.
- After #4567 merged, wire complete run sources into newly created autonomous research/monitor tasks. Existing research records must already match source identity and set; do not silently backfill them. Research completion requires current run/task source eligibility, a source set covering the run, the same source event/primary ID and a still-running action waiting on that exact task. Use persisted result/error only, never arbitrary callback text as fallback.
- Compose earlier foreground, cognition and research source guards with only this declared increment. Full-file comparisons retain unchanged code outside declared hooks, including the underlying action/review evaluation algorithms.

## Evidence

- Nine new XCTest methods authored SOURCE ONLY in the existing deliberation store fixture file: inherited metadata/context union; planner persistence/reuse; legacy source rejection; optional JSON/legacy behavior; private/paused/removed membership; queue skipping without denied-lease mutation; positive action ownership/legacy fields; review revision ownership; unreadable storage preservation.
- These fixtures were NOT executed. They do not exercise actual model/transport callbacks, research queue creation, privacy changes during execution, native tools, restarts, storage fault injection or multiple processes.
- All four dedicated source guards, `npm run check:ios`, all four checker JavaScript syntax checks and `git diff --check` passed before publication. These are not native/runtime acceptance evidence.

## Remaining

- Legacy runs/research missing proof stay stored but are not newly authorized. No migration/re-enqueue UI or reconstruction of old model text. Evalops knowledge-gap research still needs authoritative complete-source integration; it is not granted access by its synthetic agent-evalops ID.
- The source set is declared source membership plus recorded cognition context, not proof of every source behind historical prose, later native-tool outputs, attachments, research retrieval/evidence or model review output. Research's own selected-context provenance and later revocation remain unfinished.
- Action/review records do not yet persist original resource transport, so incoming response authorization uses the current stored resource identity/current contact policy, not immutable original-transport proof. No new cryptographic ownership guarantee.
- Boundary snapshots are not atomic session/task revocation or shared-file/cross-process CAS. Existing queued MQTT payloads, already sent prompts, running model/network/tool effects and archived evidence are not retracted or force-cancelled. Other dispatch entry points and lifecycle integrations still need audit.
- No native compilation/typecheck, XCTest execution, CI watching, device/model/privacy/concurrency/performance acceptance or IPA. Android #3007 and the full PR backlog are NOT complete.
