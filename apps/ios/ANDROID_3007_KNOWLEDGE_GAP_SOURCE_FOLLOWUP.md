# Knowledge-gap Research Source Follow-up

Baseline: main ca36efb28c5e2e72c620e20c4e88ccfe30e1549a after #4567. Independent iOS increment; no duplicate autonomous #4568 implementation or Android/Desktop changes.

## Implemented

- Knowledge gaps gain optional sourceConversationIds in their existing Codable record. New detector output records the conversation behind the original request used for topic/goal extraction. Require the evaluation sample to belong to the same recorded run before creating or resolving a gap.
- Preserve the complete source union when merging same-family gaps from multiple conversations. The existing 40-entry sourceRunIds diagnostic limit does NOT truncate the separate authorization source set. Store normalization copies the optional field; ordinary status updates preserve the loaded record.
- Blank/lab origins remain unproven. Merging a new observation into old prose without a source set does not manufacture one. Missing legacy optional fields stay decodable as nil; no inference from today's sessions/evicted run history.
- The bridge requires a nonempty, normalized recorded source set before creating research. Use a deterministic actual source ID, not synthetic agent-evalops, and save the entire set on GlobalResearchTask. Existing #4567 current-session gates then apply to selection, context, dispatch and result consumption, including mixed-source revocation.
- Serialize observe operations on the existing per-instance recursive lock. Make existing store dependencies injectable for isolated fixture source. Refuse unreadable research state; after a reported research save failure do not advance gap status or append a queued-research decision. No shared-file/process transaction or encrypted-store durability guarantee is added.
- Preserve existing enabled/priority/duplicate/recheck policy and resolved-decision handling. Shared bridge installation and its settings callback are unchanged; this increment adds no background-thread reads of UI-owned session state. Current conversation checks happen at the research runtime boundaries, not in the producer.

## Evidence

- Ten new XCTest methods authored SOURCE ONLY in the existing AgentEvalOpsTests file: optional JSON/legacy fields, multi-source union, legacy non-inference, lab/blank origins, wrong run/sample identity, recorded research/current scope, disabled/duplicate/malformed-source behavior, failed save, unreadable state, source preservation past the run-reference limit.
- Fixtures were NOT executed. They do not establish native Swift compilation, protected-data/keychain behavior, process/thread races or privacy revocation during work.
- Dedicated gap and existing research/cognition/foreground source guards, `npm run check:ios`, checker syntax and `git diff --check` passed. The new guard compares complete governance files outside declared hooks and freezes recorded-run, eval/trajectory, runtime/dispatch and Xcode project dependencies. No native acceptance claimed.

## Remaining

- This records request-origin conversations producing gap topic/goal text and aggregate membership, NOT every conversation behind recorded model context, attachments, tool evidence, imported/custom gap prose or later research retrieval. Those provenance paths still require audit. Host-maintained source fields are not cryptographic authentication.
- Legacy gaps/research without proof stay stored but untrusted. No re-enqueue/migration UI, reconstruction from surviving run references or automatic authorization of a synthetic namespace. This corrects the new evalops producer gap noted in #4567, not all historical provenance.
- Existing enabled-callback isolation/threading and encrypted governance load/save error reporting are unchanged and need separate review. Serialization is per bridge instance only; independent writers/processes can still race. Research and governance writes are not one atomic transaction.
- No retroactive cancellation/retraction of queued/sent prompts or running model/network/tool effects, no new OS background grant or per-token disk checks. Android #3007 and the full PR backlog remain incomplete.
- No native build/typecheck, XCTest execution, CI watching, device/runtime/privacy/performance acceptance or IPA.
