# Android #3027: concurrent ranked source-page reads

Android merge: ade1033cb1efa697805718d41aeb5411e7cdc5dc (#3027).
Integration base: deb134e35da3ec029978ddd998000a7e265ed52a (main).
The now-merged #4610 image/session/diagnostic changes are retained from main.

## Observed gap and production integration

The iOS read_pages search option already existed, but its actual implementation
read each page serially, skipped failed reads without a page diagnostic, appended
redirect bodies using dictionary order, and refreshed only part of the evidence
verification metadata. Replace that implementation with an explicitly opted-in
concurrent phase, not another model round or a new network client.

Select up to four ranked HTTPS URLs, reject credentials and de-duplicate with the
existing canonical URL policy. Each worker owns an independent native registry:
descriptor caches, replay and audit stores are not shared across threads. Invoke
the same native fetch executable/provider with copied owner/session/turn, grants,
consents and attributes, child keys hashed from the full parent identity, URL
and rank (without truncation collisions), and one shared hard
deadline no later than the original parent deadline. No network/cache consent is
added. Keep the existing provider's public-address, redirect and cache controls;
this is not new DNS-pinning or network-security acceptance.

The page phase has an eight-second monotonic wait budget, including queue time,
capped by the parent's remaining wall-clock deadline. Poll caller cancellation,
and skip new fetches when less than the native schema's minimum one second is
available, reporting insufficient budget rather than granting a fresh timeout.
Recompute the request timeout after worker scheduling and registry setup using
both remaining wall-clock and monotonic time. Reject result storage after either
deadline. Recheck caller cancellation after all workers finish; cancellation
discards even already-completed page bodies before aggregate publication while
retaining the original search discoveries and cancellation diagnostics.
Seal the collector on return and provide cancellation to registry checkpoints.
Late workers cannot modify returned aggregate evidence. A synchronous/custom
provider that ignores checkpoints may keep running; there is no force-kill or
hard real-time/native cancellation guarantee. Authorized provider-side cache work
is not made globally transactional with the returned aggregate. Up to four
workers per lookup is not a global concurrency bound across all lookups.

Merge results in original search rank, not completion/dictionary order. Keep
discovery snippets on failed reads, upgrade only actual retrieved-body items,
preserve per-page failure/deadline/cancellation summaries and underlying returned
receipts, and label incomplete page phases partial. Recompute item/document/
discovery/domain statistics and full existing integrity/conflict metadata after
merging. Verification is integrity/provenance, not semantic claim correctness.

Model-output compaction retains a bounded page diagnostic summary using ordinal,
source-URL digest, status and error code, explicitly marked non-citation evidence.
It does not truncate a URL into a new citation or discard page failures when the
rest of the evidence pack is shortened. Full local aggregate data remains subject
to existing invocation/disclosure and output-size policies, not a new memory cap.

## Other #3027 areas and boundaries

Existing weather destination/date handling, evidence prompt ledger/reprojection,
page-read reuse, source catalog routing, image medium/preview rules and provider
formatting are retained. This increment does not claim a complete re-audit or
native acceptance of all those areas. #3026/#3028 storage work already has older
iOS implementations and newer primary-storage follow-ups; it is not duplicated
inside this web PR. Remaining Android-to-iOS gaps are still active work.

## Verification boundaries

Fifteen synthetic Swift methods are authored for ranked URL admission,
concurrent entry, owner/grant/deadline propagation, denied/expired/cancelled work,
partial evidence/stats/verification, late completion, actual executeTool opt-in,
no hidden page reads, bounded diagnostic compaction, queued-worker budgets,
completion-boundary cancellation, late wall-clock results and long parent keys.
They have not been
compiled or executed. Source-contract checks compare the narrow integration with
main and inspect actual worker/merge calls, not runtime throughput or correctness.
No Swift/native tests, live network/provider/UI acceptance, measured latency, CI
monitoring or IPA are performed. Android/Desktop sources and versions are
unchanged, with iOS 15 minimum retained. No raw reports/private data are committed.

The historical web-fallback, web-tool-failure and fast-search-defaults source
guards were attempted and still fail on existing streaming-engine/cached-capacity
baseline drift. Their reported production files are unchanged against main. No
old engine behavior or fixed cache-byte limit is restored to satisfy those checks.
