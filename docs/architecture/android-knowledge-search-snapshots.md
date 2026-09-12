# Knowledge retrieval read snapshots

## Purpose

Lexical candidate selection, encrypted body decoding and reranking previously
ran inside the source database's `BEGIN IMMEDIATE` transaction and Java monitor.
Even a paged scan held the live writer until the complete query finished. Hybrid
retrieval nested the same lexical path inside its vector-resolution transaction.

The new query path initializes a pinned WAL read view under a short source lock,
then releases the writer reservation before retrieving candidates or reranking.
The read connection is query-only, has a 2 MiB SQLite page cache and disables
SQLite mmap. It is scoped to one query, not a retained plaintext result cache.
Both lexical and dense evidence in a hybrid result come from the same view.

## Consistency and publication

The snapshot captures FTS membership, pending-index keys, headers, access policy
and body references together. Concurrent writes may commit while the reader
continues to see its original revision. A shared segment lease prevents physical
reclamation of any payload referenced by that view.

Canonical knowledge payload reads also use a pinned read entry point in the
segment engine. Each read owns an independent file offset and authenticated block
buffer; it does not acquire the append monitor. Committed prefixes are immutable,
and the lease prevents their removal while new data is appended. Existing callers
of the synchronized segment `read` method retain their original behavior.

Before returning evidence, the query compares its selected encrypted headers
against current authoritative headers in bounded 32-item transactions. Deleted,
replaced or permission-modified items are omitted. This is a publication-time
check, not a guarantee against later user changes after the result has returned.
Dense resolution also checks the vector feed stamp and per-match source revision.
There is no retry-until-stable loop that can starve under continuous writes.
Hybrid retrieval checks its lifecycle generation again after final header
validation, including when it had to wait briefly for another source transaction.

Closing, exceptions and thread interruption release the read view and its lease.
Retiring the source helper invalidates its outstanding queries. Plaintext results
are still owned by their callers and existing runtime lifecycle policy; this
change does not claim that Java strings can be overwritten.

## Capacity boundaries

Indexed candidate admission remains 256 records, with lexical top-K capped at 24.
The legacy unindexed fallback retains complete keyset traversal in 32-key pages;
it no longer holds the live writer for that whole traversal. It is still O(N) in
the number of pending records. It must not be described as a 200 ms query bound
or silently replaced with an incomplete result set. Large individual bodies are
still decoded for scoring. Full FTS partitioning and progressive index-readiness
reporting remain separate work needed for corpus-scale latency.

## Validation

Device cases cover interleaved writes across pending pages, stable indexed
snapshots, permission revocation, encrypted payload leases, query-only enforcement,
idempotent closure, helper retirement, interruption and corruption propagation.
A hybrid test performs an actual concurrent write from its lexical callback and
checks that stale evidence is withheld. Another device case holds an encrypted
payload read open while an actual source append commits. JVM cases verify
same-file append, independent concurrent read offsets and authentication/complete
consumption on the new pinned entry point. Existing FTS, hybrid, admission, backup
and physical compaction regressions are included in the validation run.
The lifecycle race test deliberately holds the source monitor until the query is
blocked in publication, invalidates the semantic session, then releases the
transaction and verifies that no stale evidence escapes.

Android 1.1.104 (990) and its instrumentation APK were built and installed in place
on SM-T575. The final 66-case device run passed in 191.070 seconds. Final targeted
JVM verification passed all 61 cases in nine suites, including the new pinned-read
tests. An earlier full JVM run in this phase passed 3,806 cases with five existing
skips and zero failures/errors; it precedes the final two-line lifecycle ordering
fix. That final race is covered by the final device run, not attributed to the
earlier full-suite run. All 74 AArch64 libraries passed the 16 KiB audit.

On 1,201 actual encrypted records, a selective query decrypted one item and took
65 ms initially. A subsequent 100-query hot sample measured P50/P95/P99 of
28/46/49 ms. This is one selective local lexical workload, not ANN/model/UI time,
a broad-query bound or a corpus-size trend. A full encrypted append while holding
a pinned read completed in 273 ms: it no longer waits for that reader, but it
does not meet the 200 ms write target. The other helper timings include mixed
operations and must not be presented as one homogeneous write benchmark.

Both existing recovery drivers passed against the final APK: seven payload phases
and eight compaction phases, with six actual process deaths in total. These verify
payload rollback, durable publication, snapshot lease release and large-record
copy recovery, not physical-device reboot or a crash inside the new search method.
All isolated recovery fixtures were retained.

Latest main `7aba9f6b0` was integrated before publication, including PR #3029's
Desktop-only changes. Those changes do not alter the tested Android sources.
Exact hashes, bounded device transcripts, derived per-case JVM reports and timing
markers are recorded in `evidence/knowledge-search-snapshots-20260912/summary.json`.
No production data, pairing state or inference model was reset or downloaded.
The 100M-record, universal 200 ms and other active goal acceptance remains open.
