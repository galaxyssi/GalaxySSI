# Indexed personal-memory recall

Development version: Android 1.1.68 (954), following PR #2994 and integrating
main through PR #2995. This is an incremental lexical-index implementation,
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
The encrypted index marker is bound to the source content revision. A source revision
changed by an older writer invalidates the derived index before the next read
or observed content write, including after access/importance-only updates. Rebuilding does not
delete source memories. Legacy migration permits source metadata to arrive after
its rows. This is revision consistency, not authentication of omitted postings.

The encrypted source metadata tracks the general revision, observed revision and
content revision. Access/importance-only updates advance the general/observed
revision without writing the index marker. A writer that only advances the
general revision breaks that correspondence; its revision becomes the content
token, preserving invalidation even if a subsequent access write occurs. No
plaintext revision side table or long-lived decrypted metadata cache is added.

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

## Validation scope

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
  Fixtures suppress Global Agent observation publication to avoid background
  processing or outgoing events. Write measurements cover the storage mutation
  path, not an enabled Global Agent's observation queue or end-to-end agent turn.
  The selective benchmark starts without a browse index; existing browse-index
  maintenance is covered by separate access/point regression tests.
- Re-run the existing memory identity, rows, access and paging regression cases.

## First-candidate device validation

Validated on SM-T575 with Android 1.1.68 (954), preserving production data and
pairing. Fixtures use independent database, preference and file namespaces.
No other connected device was operated. No model was downloaded or unloaded.

- Full debug app/test APK build and JVM tests passed: 3,637 discovered,
  3,632 passed, five existing skips, zero failures/errors. The seven new matching
  and ranking tests all passed.
- Final-build device regression: 67/67 passed (15 indexed-recall, eight identity,
  ten row-storage, seven point-operation, 14 browse, six access and seven streaming
  backup tests). Large timing tests run separately, not counted here.
- Two-stage restart fixture: 129 source rows, 16 indexed at the first checkpoint;
  a distinct process resumed the same generation/cursor and returned the sole
  selected row after one decryption. Preparation PID 27205, resume PID 27289.
  Instrumentation had already ended the first process before the host force-stop;
  the host confirmed absence before starting the second process. This does not
  demonstrate an arbitrary kill in the middle of a SQLite transaction.
- Repository checks, 73-library Android 16KB audit and QNN packaging check passed.
  Packaging checks do not establish unchanged ASR/QNN inference latency.
- This candidate exposed an access-update performance regression. At 1,201 rows,
  eight-row access updates had P95 231.31ms (100/100 above 200ms). At 10,001 rows,
  new writes had one 207.34ms outlier. These samples are retained, not discarded.
  The content-revision correction and its new regression tests require a fresh
  build and same-cardinality timing before final acceptance.

App APK SHA-256:
`bf65596469a4c72330e42e4f0646776257ad137a10d4594b06d340e8b7d0c49d`.
Test APK SHA-256:
`0e13bc31e192275eaa3c1cd4147d3f8ec7abe8a400a277af2991d94e7b2bf383`.

Local evidence is retained under `build/memory-indexed-recall-v1168-*`, including
the complete build, instrumented regression/restart logs and raw benchmark
logcat. No source memory body or production message is recorded in benchmark
reports.

All 800 first-candidate samples and independently recomputed percentiles are in
[the first-candidate report](android-memory-recall-first-candidate-20260911.json).
There were 102 operations above 200ms: one new write at 10,001 rows, 100 eight-row
access updates at 1,201 rows, and one eight-row access update at 10,001 rows.
The two timing tests passed their correctness assertions, not the latency goal.

## Content-revision correction

The correction removes index reads/writes from known non-content updates. Its
build passes 3,638 JVM tests with five existing skips and no failures/errors,
including six new content-revision tests. The 73-library alignment and QNN
packaging checks pass again. All 69 device regressions pass, including two new
tests proving unchanged index ciphertext on access/importance updates and
preserved older-writer invalidation after an access update. Both restart stages
also pass again (PIDs 29188 and 29268, 129 retained source rows, one candidate
decryption). The same-cardinality timing retest is in progress; first-candidate
numbers do not certify this build's latency.

Corrected app APK SHA-256:
`4f918ec5ce38a5e64f9b0cf3619a21e7c72827fe4b47393fda9deffd091bda55`.
Corrected test APK SHA-256:
`785e9ef83cd37f55eacde75f22a544b04aba1d6abda322885f7f34d73d2dc597`.

## Remaining work

Broad/common terms may still require many source decryptions. Rare-term success
must not stand in for broad, multilingual, cold or concurrent query benchmarks.
Pre-index and legacy giant-JSON migration, some bulk mutations, long-record
parsing, count API migration to 64-bit throughout, sharded compressed event
storage, persistent native ANN and vector/reranker quality remain unfinished.
The current SQLite dictionary/posting layout needs measured storage and write
amplification before any large-scale suitability claim. No 100M-record data set
has been loaded or tested by this phase.
