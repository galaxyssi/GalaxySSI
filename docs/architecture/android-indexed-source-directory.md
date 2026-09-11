# Indexed knowledge source directory

Android 1.1.94 development follows streaming knowledge backup in PR #3013.
The directory, encrypted-source migration, retained-corpus tests and 128 shared
regressions have passed on SM-T575. The full 100M+ memory, Run Kernel, tracing
and ordinary Agent Loop DAG goals remain open.

## Problem

The previous source page returned at most 50 groups, but each request executed
`GROUP BY` and `count(DISTINCT ...)` over all source metadata. It also built a
composite source index synchronously during older-schema upgrades. Bounded
returned rows did not imply bounded query work.

## Directory and migration

Schema 8 adds an empty source directory, a source membership table and a single
checkpoint/count row. It does not decrypt, copy or rewrite original source bodies
or vector ciphertext. New indexes belong to the initially empty derived tables;
the earlier synchronous `knowledge_source_recent` index build is no longer
required. Existing copies of that index are not dropped during upgrade.

Source inserts, updates and cascading deletes maintain membership in the same
SQLite transaction. Membership changes maintain per-source counts and the most
recent representative. Deleting a representative seeks the next member through
the membership index; it does not rescan a complete source. Blank-source notes
remain distinct and are not grouped together.

Old rows are enrolled by at most 64 primary-key positions per transaction, with
one lookahead row. Already-tracked live inserts still consume the page budget.
The checkpoint commits with enrolled members and counters. Mutations before or
after the checkpoint maintain membership immediately, avoiding a missed-row
window. Existing membership must match the actual source metadata.

Background maintenance yields between batches and resumes from the SQLite
checkpoint when the store reopens. It does not depend on a configured embedding
model, model downloads or inference enablement. Errors remain visible rather
than resetting the checkpoint. Explicit retry does not discard stored sources.

## Indexed reads and readiness

The directory stores bitwise-inverted timestamps so one ascending tuple index
can seek descending timestamps and ascending group keys, including tied times
and signed 64-bit timestamp extremes. Pages use `(sort_updated, group_key) >
(?, ?)` and a bounded limit. Counts are point reads. Representative metadata is
still authenticated through the existing source header reader, including source
identity and timestamp checks.

During migration, exact source counts/pages raise an explicit not-ready result.
The source page shows index preparation instead of an empty completed corpus,
subscribes to completion/failure and discards its observer when detached. Control
center counts distinguish preparation/errors from a real zero. Non-UI consumers,
including Obsidian projections, cannot mistake a partial directory for a complete
empty result. Existing browse revisions continue to invalidate stale cursors.

## Device evidence

- Twelve bundled-SQLite cases passed in 1.287 s: batching, live changes, head
  deletion, rollback, missing/ignored checkpoints, reopen, extreme timestamps
  and query plans. These are metadata fixtures, not complete encrypted memories.
- Three actual encrypted-source tests passed in 12.771 s: schema-7 background
  migration, visible failure followed by retry, and completion/cursor lifecycle.
  Migration preserved ciphertext and did not configure an embedding model.
- The retained 10,001-source encrypted backup corpus passed all 201 pages in a
  147.964 s test. Every source appeared exactly once in descending order. Pages
  authenticated 10,001 headers and decrypted zero source bodies. Original header
  and chunk ciphertext hashes remained identical. A cursor survived a reopen
  after page 100.
- Opening the schema-7 corpus took 28 ms; its asynchronous metadata enrollment
  took 9,367 ms; reopening the completed directory took 23 ms. These are database
  timings, not Android Activity startup or end-to-end UI performance.
- Full authenticated page latency was P50 624.244 ms, P95 916.665 ms, P99
  987.571 ms and maximum/first page 1,200.351 ms. The 200 ms full-page goal
  **has not passed**.
- In a separate five-pass profile of 50 existing sources, mean indexed seek was
  1.04 ms, header AEAD decryption was 251.96 ms, and 50 identity HMAC operations
  were 190.10 ms. Authenticated summaries averaged 637.49 ms; complete pages
  averaged 860.12 ms. These independent measurements identify cryptographic
  per-row work as the remaining dominant cost, not an additive accounting trace.
- A separate test committed 64 of 137 membership records, terminated its actual
  Android process and resumed in a different PID. Verification passed in
  2.177 s, with all 137 encrypted records preserved. Only that recovery fixture
  was cleaned up; the 10,001-source corpus remains on the tablet.
- All 128 shared device regressions passed in 850.389 s, with no skips. This
  includes source paging, backup, counters, FTS, native/hybrid retrieval, vector
  enrollment/ledger and selected model lifecycle tests using the existing pinned
  test model. FTS hot-query P95 was 42 ms on 1,201 sources; the three-document
  real hybrid retrieval fixture returned top-1 recall 3/3 and hot-query P95 146 ms.
- JVM results: 3,751 tests across 537 suites, zero failures/errors and five
  existing skips. Repository checks and all 74 native-library 16 KB alignment
  checks passed. Android 1.1.94 (980) was installed without resetting app data.

Raw per-page and component samples are in
[`evidence/android-source-directory-20260912`](evidence/android-source-directory-20260912/README.md).
No database, plaintext source, portable backup archive or user data is published.

## Remaining validation and limits

- UI rendering/interaction acceptance remains separate. Process-death evidence
  is not a physical-device-reboot or cross-device test.
- Source header authentication still uses the current storage cipher. Removing
  SQL aggregation alone does not prove a 200 ms full-page latency bound.
- `stats()`, whole-source access membership and whole-source Obsidian export
  retain their previous aggregate/collection APIs. They need further work.
- This is derived-index maintenance, not storage sharding or a generational
  restore implementation. No 100M capacity claim is made.

## Next implementation boundary

Optimize authenticated metadata access without dropping identity checks or
keeping unbounded decrypted source caches. Evaluate the existing
Keystore-wrapped row-key mechanism and an authenticated disk-backed preview
index with a fixed RAM cache, preserving source revisions and background/lock-screen
key clearing. A bounded cache must not impose a fixed retained-record count.
Legacy ciphertext must remain readable, and migration must yield outside the UI
thread. Measure the unchanged retained corpus again, including cold/warm pages,
mutation invalidation and process restart. A fast SQL query alone is not the
complete retrieval target.

Partitioned source storage and streaming per-source membership/export APIs still
need further implementation. The existing NDK retrieval engine and personal-memory
payload segments are not changed here; their presence does not demonstrate
100M-source end-to-end capacity or latency acceptance.
