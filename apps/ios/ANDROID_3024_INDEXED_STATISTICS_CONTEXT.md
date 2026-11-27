# Android #3024: truthful indexed knowledge context statistics

Android merge: `3ee726dd47a59873f1b51014eecbd5dff4786744`.
Incremental predecessor: iOS #4606 at
`d518ac4220dda2a83c09f24c0f4097469b901afe`, including #4605, #4604,
#4603, #4602, #4601, #4600 and #4596. This formal main-targeting PR keeps
those shared commits; the full-main review also includes the physical store,
leases/batching, periodic maintenance, checked durability, allocation recovery,
statement/read-connection reuse, compaction, copy checkpoints and record headers.

## Committed-statistics integration follow-up

The branch now merges updated #4606 at `f6eb451d1`, including the updated
primary/copy/compaction/statement/source chains and #4625/#4623/#4621/#4619/
#4616 ancestry. These prerequisites remain part of the full main diff, not
newly delivered #3024 features. The existing formal PR/base main is retained
without a prerequisite merge wait, duplicated patches or author approval.

One actual producer gap is corrected here: `knowledgeStats()` previously
entered the canonical writer lock. It now owns a pinned committed query-only
view, reading transactional item/source counters, both completion flags and
the covering latest-timestamp value in one SELECT. It does not enter the
canonical writer, read its own uncommitted transaction, decode a body, count a
corpus, request lexical repair or invoke a model. The dedicated view path
deliberately avoids the general read helper's asynchronous index-retry effect.
Underlying counter tables/triggers, catalog mutations, crypto and indexes are
unchanged. The new view has the same physical retention/managed-close and
lifecycle admission as other committed adapters, not new background authority.
Protected-data/admission failures remain truthful unavailability, not zero.

Require native INTEGER types for all five values, nonnegative counts/time,
full-width Int64 zero/one completion flags, exact native count conversion and
SQLITE_DONE after the single row. REAL/TEXT corruption or wide flags must not
silently truncate into apparently valid totals/status. Return partial counts
only when valid completion flags actually say indexing is incomplete.

Five additional synthetic methods cover old committed counters while another
writer is held, rejection of own uncommitted reads, malformed types/wide flags,
partial versus exact wide metadata, and no scheduling of a known repair task.
The complete scope now contains 267 authored methods: 248 inherited primary/
source fixtures, 14 original context methods and these five. None was compiled
or executed; this is not timing, concurrency, UI or native acceptance evidence.

The statistics guard pins updated #4606 for full retained consumer/project and
database comparisons. Only the declared count-read admission/validation block
is normalized for older storage guards, whose assertions remain. It directly
checks the new single-view typed SQL and absence of bodies/repair/aggregate
fallbacks. Private/task-scoped lazy capture and metadata-only prompt rules are
unchanged. Same-store physical locks and OS scheduling can still cause waits;
no universal nonblocking or latency guarantee is introduced.

## Existing producer and actual remaining gap

iOS already reads transactional item/source directory counters and the covering
timestamp index, retaining 64-bit SQLite values and incomplete-enrollment status.
The original consumer increment left that producer unchanged; the follow-up
above changes its read admission and typed validation, not its mutations/triggers,
crypto, schemas or covering index. Do not claim a new aggregate-query replacement
where the indexed path already existed. The gap was in consumers: a failed
indexed read enumerated an in-memory UI cache and reported it as an exact total;
the status command rendered partial totals as exact and grouped the cache;
the phone planner did not carry this count-status context.

## Consumer and command integration

Remove the cache-enumerating statistics fallback. A failed indexed read now has
an explicit countsUnavailable flag, forces countsComplete=false, and provides
no numeric totals in its structured context. Unavailable is not mislabeled as
zero or active indexing. Codable defaults preserve old snapshots without the
new unavailable flag. Existing complete/partial numeric fields retain native
Int width on supported 64-bit iOS 15+ devices and are formatted with Int64.
Prompt metadata serializes counts as decimal strings, not lossy Double values.

The actual local knowledge-status command queries at most ten indexed source
groups, rather than grouping the entire cached item list. Report complete totals,
explicit lower bounds while indexing, or unavailability. Do not append an empty
knowledge claim when enrollment/source preparation is pending or failed. Add
English fallbacks and Chinese Localizable resources using the configured
response language. The result carries item/source/time/completeness/status
parameters, and the real delivered-command trace records those bounded fields.
No raw database error, source body or identifier list is added to this trace.

## Planner capture and privacy

Capture a single indexed statistics snapshot only for declared knowledge-search
planning in a non-private conversation. Other/private tasks do not even invoke
the reader closure. Persist the optional typed snapshot with the existing
planning request; old journals missing it decode to nil rather than an exact
empty database. Prompt construction rechecks the same scope, including restored
requests, and emits only count/time/status metadata explicitly labeled as not
retrieval evidence. It neither queries the corpus again during rendering nor
grants access to knowledge content. Unlike Android's unconditional runtime
summary, this iOS adaptation preserves the existing private-conversation and
task-data-minimization boundary. No new tool authority or body disclosure occurs.

This increment updates the overview command, its trace and planner metadata;
it does not redesign every existing compact settings/dashboard count badge.
Nor does it change source grouping identity, UI item caches used by unrelated
features, model routing or knowledge access policy.

## Verification limits

Fourteen synthetic Swift methods authored and registered, not compiled/executed:
indexed wide-count preservation; unavailable versus exact-zero/indexing status;
English/Chinese partial summaries; complete summaries; legacy/new Codable
semantics; skipped private/non-knowledge reads; single metadata-only capture;
partial prompt context; restored-request privacy; planning snapshot round-trip
above 2^53; actual overview from indexed sources with an empty UI cache; partial
directory without false-empty output; unavailable counters without fallback;
and synthetic wide metadata counters plus EXPLAIN covering-index admission.
The wide counters are intentionally synthetic state, not billions of records
or a measured latency/capacity benchmark. Existing indexed-stat mutation/reopen
fixtures remain untouched and are not claimed as newly executed.

The earlier review scope contained 156 authored Swift methods, not passing tests;
the integrated totals and remaining limits are stated above.
The source guard pins the predecessor, limits changed consumer/model/service/
localization/project sections, verifies actual producer and consumer call sites,
and retains all eight older source guards through a checked normalization hook.
Source checks cover nine scope guards and their JavaScript syntax, iOS project
structure, changed-source/document literal-Han placement and diff whitespace.
No Swift compile/typecheck, native SQLite/XCTest, UI/device/concurrency/recovery
acceptance, full npm check, CI watching, IPA, approval or merge.

Android #3022 was separately inspected: iOS already streams authenticated source
snapshots into encrypted SQLite ordering scratch and performs two ordered output
passes. That observation is not proof of full #3022 parity; ephemeral key
lifetime, scratch/admission/cleanup and error boundaries still need their own
comparison. No unrelated projection changes or claim of completion is included.
Central directory/FTS/vector-control sharding, unknown orphan inventory, exact
uncounted dead-byte accounting, native acceptance and the full Android-to-iOS
backlog remain unfinished. No Android timings, hard latency/RSS bound or
hundred-million-record acceptance is claimed.
