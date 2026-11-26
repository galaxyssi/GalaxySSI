# Knowledge-gap Research Source Follow-up

Baseline: main ca36efb28c5e2e72c620e20c4e88ccfe30e1549a after #4567. Independent iOS increment; no duplicate autonomous #4568 implementation or Android/Desktop changes.

## Implemented

- Knowledge gaps gain optional sourceConversationIds in their existing Codable record. New detector output records the conversation behind the original request used for topic/goal extraction. Require the evaluation sample to belong to the same recorded run before creating or resolving a gap.
- Preserve the complete source union when merging same-family gaps from multiple conversations. The existing 40-entry sourceRunIds diagnostic limit does NOT truncate the separate authorization source set. Store normalization copies the optional field; ordinary status updates preserve the loaded record.
- Blank/lab origins remain unproven. Merging a new observation into old prose without a source set does not manufacture one. Missing legacy optional fields stay decodable as nil; no inference from today's sessions/evicted run history.
- The bridge requires a nonempty, normalized recorded source set before creating research. Use a deterministic actual source ID, not synthetic agent-evalops, and save the entire set on GlobalResearchTask. Existing #4567 current-session gates then apply to selection, context, dispatch and result consumption, including mixed-source revocation.
- Serialize observe operations on a per-instance background Task chain and protect state with the existing recursive lock. Each item waits for its predecessor, reads the latest installed MainActor/Sendable settings callback without holding the lock across the await, then performs storage work in the utility worker. Return a discardable Task handle so fixtures/owners can wait without blocking the main thread. Identity-checked cleanup cannot clear a newer pending tail. Store dependencies remain injectable. Refuse unreadable research state; after a reported research save failure do not advance gap status or append a queued-research decision. No shared-file/process transaction or durability guarantee is added.
- Preserve existing enabled/priority/duplicate/recheck policy and resolved-decision handling. Existing production installation syntax is unchanged, but the callback now has explicit MainActor isolation; no direct background-thread UI settings read. Resolved observations do not require a policy read. Current conversation checks still happen at research runtime boundaries, not in the producer.

## Evidence

- Twelve new XCTest methods authored SOURCE ONLY in the existing AgentEvalOpsTests file: the ten source/persistence methods plus main-actor policy placement/ordered observation and policy read at execution rather than enqueue. Bridge fixtures now explicitly await their work handles before inspecting storage.
- Fixtures were NOT executed. They do not establish native Swift compilation, protected-data/keychain behavior, process/thread races or privacy revocation during work.
- Dedicated gap and existing research/cognition/foreground source guards, `npm run check:ios`, checker syntax and `git diff --check` passed. The new guard compares complete governance files outside declared hooks and freezes recorded-run, eval/trajectory, runtime/dispatch and Xcode project dependencies. No native acceptance claimed.

## Remaining

- This records request-origin conversations producing gap topic/goal text and aggregate membership, NOT every conversation behind recorded model context, attachments, tool evidence, imported/custom gap prose or later research retrieval. Those provenance paths still require audit. Host-maintained source fields are not cryptographic authentication.
- Legacy gaps/research without proof stay stored but untrusted. No re-enqueue/migration UI, reconstruction from surviving run references or automatic authorization of a synthetic namespace. This corrects the new evalops producer gap noted in #4567, not all historical provenance.
- Encrypted governance load/save error reporting remains unchanged and needs separate review. Serialization is per bridge instance only; independent writers/processes can still race. Research and governance writes are not one atomic transaction. Observation is now asynchronous; no immediate synchronous research visibility, new scheduler wake or measured timing/queue-concurrency acceptance is claimed. A permission can still change after the main-actor read; the runtime must keep its later live gates.
- No retroactive cancellation/retraction of queued/sent prompts or running model/network/tool effects, no new OS background grant or per-token disk checks. Android #3007 and the full PR backlog remain incomplete.
- No native build/typecheck, XCTest execution, CI watching, device/runtime/privacy/performance acceptance or IPA.
