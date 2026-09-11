# Indexed personal-memory recall

Development version: Android 1.1.67 (953), following PR #2994. Build and device
acceptance are pending. This is an incremental lexical-index implementation,
not delivery of the 100M+ storage/vector engine or a proven 200ms guarantee.

## Actual retrieval path

`EncryptedAgentMemoryStore.recall` now uses a transactional derived index rather
than `loadItems()`. Original encrypted rows remain authoritative. A dictionary
maps HMAC-SHA256 tokens to integer IDs; a `(term_id, doc_id)` posting table uses
integer keys and `WITHOUT ROWID`. This avoids repeating a full token and full
row-key string for every posting. SQLite documents the suitability of this
layout for small composite-primary-key rows, not a universal speed guarantee:
[WITHOUT ROWID](https://www.sqlite.org/withoutrowid.html).

The existing lexical semantics are preserved: case folding, whole-value and
reverse substring matches, structured model/product identifiers, word fragments
and Chinese bigrams. Forward clauses use the least frequent required gram;
reverse containment uses exact value tokens for query substrings. Long queries
use a broader gram union instead of quadratic substring expansion. Every
candidate is checked against its encrypted source and ranked using the original
weights. No arbitrary candidate-count cutoff is introduced.

Posting streams use 16-ID keyset pages and a merge heap; duplicate candidates
are read once. A bounded top-eight heap preserves score, importance, timestamp
and original-position tie ordering. It does not load or sort the whole corpus.
Scratch space still depends on query term count and individual record size;
this is not yet the shared fixed native-cache architecture.

## Consistency and recovery

The source and index are updated in the same SQLite transaction, including
new memories, bulk replacement, edits, privacy/status changes, deletion,
scope rebinds and backup restoration. Access-time-only changes preserve
posting membership. Bulk replacement writes metadata before removing obsolete
rows; count checks therefore occur after the complete mutation transaction.
The encrypted index marker is bound to the source revision. A source revision
changed by an older writer invalidates the derived index before the next read
or observed write, including access/importance-only updates. Rebuilding does not
delete source memories. Legacy migration permits source metadata to arrive after
its rows. This is revision consistency, not authentication of omitted postings.

New empty stores start with a ready index and maintain it incrementally.
Existing row stores build the index in 16-record transactions, committing the
keyset cursor with each page. Writes also maintain the partial index, including
inserts behind its cursor. Reopening a process resumes from the stored cursor;
cleared or superseded generations cannot be resurrected by an old worker.

Before migration is ready, recall scans source rows in 128-key pages and keeps
only the best eight candidates. It returns complete matching results rather
than an incomplete index result, then schedules background index continuation.
This removes the whole-corpus JVM list but does not make pre-index recall fast.
Backfill failure preserves source records and leaves a resumable checkpoint.

## Privacy boundaries

The Android Keystore HMAC key derives a domain-separated, generation-specific
HMAC key for a bounded indexing/query operation. Standard JCA `Mac` computes
tokens locally; software MAC/key objects are discarded after the operation and
owned byte buffers are cleared. No plaintext token/body or raw derived key is
stored in the posting tables. Existing encrypted rows and their associated-data
checks are unchanged. There is no cloud/provider call or model lifecycle change.

This does not promise JVM-wide secret zeroization: the JCA provider owns an
internal key copy. Token equality/frequency, row linkage, counts and access
patterns remain observable to someone who can inspect the database. It is not
equivalent to fully encrypted index pages. Selected-source validation prevents
an index entry from making private/inactive/expired data recallable, but a keyed
index is not a complete authenticated proof against arbitrary omission attacks.

Caller scope policies remain separate from candidate ranking; this change does
not establish full namespace-filtered semantic retrieval or rewrite Agent
routing. Those still require end-to-end acceptance.

## Validation plan

- Pure matching-superset checks over multilingual, structured and randomized
  inputs; preserve legacy weights and stable top-K ordering.
- Real SQLite/Keystore tests: selective reads, many candidate pages, update,
  delete, privacy, expiry, stale metadata, index rollback, interrupted backfill,
  background completion, legacy migration and wrapper reopen.
- Stage an interrupted index in a namespaced device fixture, terminate the app
  process, then verify a distinct process resumes the persisted generation and
  cursor with all source rows intact. This is a process-restart test, not a
  device-reboot or month-long execution acceptance.
- Measure actual public warm recall and new writes at 1,201 and 10,001 physical
  records, 100 operations per category/size; retain raw samples, P50/P95/P99,
  maximum and every operation above 200ms. Warm repeated recall includes the
  existing five-minute access-write throttle; distinguish it from fresh access
  persistence, migration and cold-start timing.
- Re-run the existing memory identity, rows, access and paging regression cases.

## Remaining work

Broad/common terms may still require many source decryptions. Rare-term success
must not stand in for broad, multilingual, cold or concurrent query benchmarks.
Pre-index and legacy giant-JSON migration, some bulk mutations, long-record
parsing, count API migration to 64-bit throughout, sharded compressed event
storage, persistent native ANN and vector/reranker quality remain unfinished.
The current SQLite dictionary/posting layout needs measured storage and write
amplification before any large-scale suitability claim. No 100M-record data set
has been loaded or tested by this phase.
