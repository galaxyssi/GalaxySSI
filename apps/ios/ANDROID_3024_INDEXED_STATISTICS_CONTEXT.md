# Android #3024: truthful indexed knowledge context statistics

Android merge: `3ee726dd47a59873f1b51014eecbd5dff4786744`.
Incremental predecessor: iOS #4606 at
`d518ac4220dda2a83c09f24c0f4097469b901afe`, including #4605, #4604,
#4603, #4602, #4601, #4600 and #4596. This formal main-targeting PR keeps
those shared commits; the full-main review also includes the physical store,
leases/batching, periodic maintenance, checked durability, allocation recovery,
statement/read-connection reuse, compaction, copy checkpoints and record headers.

## Existing producer and actual remaining gap

iOS already reads transactional item/source directory counters and the covering
timestamp index, retaining 64-bit SQLite values and incomplete-enrollment status.
That exact database implementation, its mutations/triggers, crypto, schemas and
covering index remain unchanged. Do not claim a new aggregate-query replacement
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

The full-main scope contains 156 authored Swift methods, not 156 passing tests.
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
