# Transactional memory index statistics

Android 1.1.92 / knowledge schema 7, based on merged PR #3011 (`e27cba403`).
The 100M+ full-memory and other active goals remain open.

## Problem and implementation

`KnowledgeSemanticController.refreshCounts()` previously counted every matching
row in `knowledge_vectors` and `knowledge_vector_queue` after indexing batches.
The vector primary key begins with the item key, not the model key, so the first
count also inspected other models' rows. Moving that scan to a background thread
did not make its database-lock duration independent of corpus size.

Schema 7 maintains per-model signed 64-bit counters for actual vector rows and
pending queue rows. It counts committed chunks of incomplete documents, not only
completed documents. Source bodies, authenticated vector bytes and completion
markers retain their existing formats and remain authoritative.

- SQL triggers update a row's tracking flag and its counter within the same
  transaction as insertion/deletion. Queue `ON CONFLICT DO NOTHING` is idempotent.
- Recursive triggers are enabled on every knowledge connection so replacement
  statements also run deletion triggers. This is covered by replacement and
  existing migration/integrity regressions, not assumed from the old default.
- Source replacement, source deletion and model removal use existing foreign-key
  cascades. Model removal cannot decrement another model's counter.
- Counter overflow/underflow or a silently ignored update aborts the transaction.
  Missing counter state is reported rather than silently reset to zero.
- Tracked row identities are immutable; source revisions still use the existing
  delete/insert path. A tracked row cannot be reset and counted twice.
- UI refresh performs model-key and two fixed checkpoint-key lookups. It neither
  decrypts sources/vectors nor opens an inference model.

## Upgrade without a blocking corpus rewrite

Migration adds default tracking columns without new CHECK constraints or a new
index over old rows, creates two sweep cursors, and copies only the small model
directory. Each cursor uses the table's existing primary-key order. Already
tracked rows still consume the page budget; filtering after LIMIT prevents an
unbounded scan through an already counted prefix.

This uses SQLite's documented metadata-only ADD COLUMN path, not a new index or
table rewrite during startup. CHECK constraints on added columns can instead
force existing-row validation, so new tracking changes are validated by triggers.
See [SQLite ALTER TABLE](https://sqlite.org/lang_altertable.html) and
[SQLite trigger semantics](https://sqlite.org/lang_createtrigger.html).

Legacy rows are counted in transactions of at most 64 rows per table plus one
lookahead. The tracking updates, counter delta and sweep cursor commit together.
Inserted rows are counted immediately, including keys behind an old cursor.
Uncounted deletions contribute no negative delta; counted deletions subtract once.
Close/reopen and process termination resume the same persisted cursors.

Counters for legacy models are explicitly partial until both sweeps complete.
The model page displays counts collected so far and a counting state. New models
start with complete counters even while another model's legacy sweep remains.
The metadata worker reports a separate count error without changing model
enablement or the inference phase. Initial shared-database/open errors still use
the controller's existing error path.

`KnowledgeCountWorker` is an independent durable metadata worker. It does not
require an installed/enabled model and cannot download/load one. Each SQLite
transaction releases the store monitor before the next page. A 15-second worker
quantum yields to a durable successor, not a lifetime limit; no memories or
unfinished counts are discarded. A serial controller coalesces requests to at
most one pending successor. Counter snapshots are published at quantum boundaries,
not posted to the UI for every scanned row/page. Privacy reset/close cancels this
work and a worker retains its original database handle rather than reopening a
new store after reset.

The worker's independence does not add a new uninstalled-model startup refresh:
the controller still refreshes counts during initialization only when its model
artifact is installed. The no-model device case explicitly requests maintenance.

## Privacy and limits

These counts, tracking bits and opaque-key cursors are derived local metadata,
not authenticated external checkpoints. Shape checks detect malformed state,
but valid privileged metadata replacement/whole-database rollback is outside
this change's claim. Existing source/vector AEAD and revision checks remain.
No private memories, models or timing evidence are uploaded by runtime code.

No count or action quota is introduced. Signed 64-bit overflow fails explicitly
rather than wrapping, truncating records or accepting an inconsistent write.
Finite storage, fsync, lock contention and OS scheduling still apply: bounded SQL
work is not an unconditional 200ms latency guarantee.

Other full-source aggregations, full source/index partitioning, semantic routing,
large-corpus neural recall and end-to-end UI/ASR concurrency need separate evidence.
This change does not complete Run Kernel integration, full tracing or ordinary
Agent Loop DAG acceptance.

Specifically, `SQLiteAgentKnowledgeStore.querySnapshot()` still includes full-source
`stats()`, and `KnowledgeSourcePaging` still aggregates groups while producing a
bounded result page. Also, `AppBackupRecords` calls `visitNonMemoryFields()`, whose
knowledge field still uses the whole-array `SQLiteAgentKnowledgeStore.exportJson()`.
Personal-memory streaming does not make that knowledge backup path streaming.
These are verified remaining implementation gaps, not completed scale features.

## Verification

The new encrypted-source tests cover partial-document counts, cascade updates,
idempotence/replacement, v6 upgrade, no source decryption, concurrent live changes,
already counted prefixes, transaction rollback, ignored cursor/row/counter writes,
missing/corrupt metadata, overflow/underflow and concurrent maintenance/reopen.

The separate worker test uses synthetic embeddings in an isolated database and
asserts that metadata recovery succeeds with no installed or enabled encoder.
The explicit recovery test kills a process after counting 64 vectors and 17 queue
rows, then checks 131 vectors, 17 queued sources and 148 encrypted original records
in a fresh process. It never resets the App or targets a production database.

The explicit SM-T575 SQL scale test has 1,000,000 vector rows and 1,000,000 queue
rows, but synthetic vector bytes, no genuine source bodies and no neural model.
It compares full counts at four cardinalities, times the upgrade and every bounded
backfill transaction, mutates before/after the cursor, reopens mid-run and at the
end, then measures point reads and additional writes with commit/fsync included.
It retains original timing samples and the isolated fixture. No OS cache drop;
the old baseline warms caches before the new path. This is metadata acceptance,
not one million complete memories or hundred-million-record capacity acceptance.
The synthetic vectors share one parent document and sequential ordinals; backfill
timings do not represent the random I/O distribution of a full HMAC-keyed corpus.

## Results

### Initial candidate and scale-discovered defect

Matching App and test APKs were built and installed on **SM-T575 only**, preserving
the existing first-install time and user data. Android version code is 978.
APK SHA-256: `55b9f383f9dc9c9b67033811ab4a674b3604f811e816b1051795691986f9e760`.

- Gradle build: 12m21s, using the checked-in 8GiB default heap.
- JVM: 3,750 cases, zero failures/errors, five existing skips, 537 suites.
- Repository guard and all 74 native AArch64 16KiB alignment checks passed.
- New device cases: 15/15 passed in 61.599s, including model-independent work.
- Existing device regressions: 75/75 passed in 513.653s. These include source
  paging, change-log integrity, vector enrollment, native retrieval and model
  lifecycle. The 1,201-document completion case retained every document.
- Actual process death: PID 4856 committed counts 64/17 and terminated itself;
  new PID 4955 verified that checkpoint, finished at 131/17, and checked all 148
  encrypted source contents in 3.147s. Separate fixture cleanup passed. This is
  not a physical device-reboot or full Agent Run Kernel recovery claim.
- Existing local BGE fixture: 3/3 Chinese top-one answers, 100 hot queries,
  P50/P95/P99 134/176/182ms. The fixture has four native nodes, not a large corpus;
  timings were higher than the preceding 1.1.90 candidate's 113/144/146ms sample.
  These uncontrolled runs establish neither a speedup nor unchanged performance.
- Retrieval admission: all 192 samples across six contention/invalidation phases
  were below 200ms; maximum 111ms. This is a separate synthetic workload.

[Initial regression evidence](evidence/android-memory-counts-20260912/initial-regression.json)
includes all 192 admission samples, artifact identity and measurement scope.

The initial million-row backfill was intentionally stopped after more than
11 minutes without reaching its first 4,096-page checkpoint. PID 5125 was still
using a CPU core; this was not a lost connection or an observation timeout.
The isolated database `test-count-scale-db7e1ae4dda44fa39e09e72add9a7c2b.db`
and four baseline CSVs were preserved. In-memory partial-page timings were not
exported before termination and cannot be treated as measured passes.

Review found that `(item_key,model_key,ordinal)>(?,?,CAST(? AS INTEGER))`
only sought the first two index columns, rescanning the document prefix for
every page. A host SQLite 3.53.1 EXPLAIN reproduction confirmed the shortened
seek. Bare parameters retain column affinity and the full three-column seek.
The corrected device test now requires every cursor key in the actual query
plan, and a many-chunk encrypted document checks numeric ordering across restart.
The previously passing `SEARCH table` assertion was insufficient.

### Corrected candidate

The corrected APK SHA-256 is
`615a0ebe358f690bac944e7c94716a131ed6b4f17d1804bab99d7d9a391d89a6`.
It built in 7m45s with the verified `-Xmx8192m` daemon. All 3,750 JVM cases
remained free of failures/errors (five existing skips), the repository guard
passed, and all 74 native libraries passed alignment. App and matching test APKs
were installed on T575 without uninstalling/resetting data.

All 16 focused device cases passed in 65.84s. This includes actual bundled-SQLite
full-key seek plans, numeric multi-chunk pagination and model-independent workers.

The exact interrupted million-row database resumed from 251,008 counted vectors
and 251,008 queue rows. In 791.988s it completed 11,703 pages per table, reopened
mid-run and after completion, applied deletions on both sides of the cursor,
then accepted 128 new source/vector transactions. Both actual table counts and
counters finished at **1,000,126**, with every remaining row marked tracked.

| Resumed SQL fixture operation | Samples | P50 ms | P95 ms | P99 ms | Maximum ms | >200ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Old full counts, repeated before backfill | 32 | 362.936 | 368.297 | 372.657 | 372.657 | 32 |
| Vector backfill transaction | 11,703 | 33.332 | 38.104 | 42.399 | 70.238 | 0 |
| Queue backfill transaction | 11,703 | 31.948 | 36.103 | 41.330 | 218.200 | 1 |
| New point-count transaction | 256 | 0.406 | 0.460 | 0.486 | 0.547 | 0 |
| New source/vector SQL write transaction | 128 | 1.874 | 4.180 | 19.608 | 29.179 | 0 |

The single >200ms queue page was sample 3,115 at 218.199731ms; it is retained.
The first count after reopening took 0.857962ms. Database size after checkpoint
was 850,718,720 bytes. This is not full encrypted-memory write latency or neural
retrieval: the fixture excludes source bodies, valid vector AEAD, Keystore,
embedding and UI. Commit/fsync is included; OS caches were not dropped.

[Resumed fixture evidence](evidence/android-memory-counts-20260912/resume-summary.json)
indexes all 23,822 raw samples in 19 files of at most 1,500 samples / 22,691 bytes.
Every sample ordinal, percentile and outlier count was independently recomputed
from CSV before archiving. No timings were filtered out.

### Fresh full-scale repeat

A new million-vector / million-queue fixture passed in 1,120.2s on the corrected
APK, including the full migration, every backfill page, mid-run reopen/deletions,
final reopen, point reads, 128 new writes and exact counts/tracking verification.
Migration took **8.355423ms**; the first reopened count took **0.864192ms**.
Final vector and queue counts were both **1,000,126** and database size was
850,718,720 bytes. This fixture is retained separately from the recovered one.

| Fresh SQL fixture operation | Samples | P50 ms | P95 ms | P99 ms | Maximum ms | >200ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Old full counts, 1,024 rows/table | 32 | 0.374 | 0.441 | 0.476 | 0.476 | 0 |
| Old full counts, 10,240 rows/table | 32 | 3.851 | 4.764 | 4.927 | 4.927 | 0 |
| Old full counts, 102,400 rows/table | 32 | 36.464 | 37.390 | 39.366 | 39.366 | 0 |
| Old full counts, 1,000,000 rows/table | 32 | 368.834 | 383.840 | 3,019.949 | 3,019.949 | 32 |
| Vector backfill transaction | 15,625 | 33.635 | 37.951 | 42.051 | 88.462 | 0 |
| Queue backfill transaction | 15,625 | 32.312 | 36.178 | 42.109 | 175.711 | 0 |
| New point-count transaction | 256 | 0.417 | 0.473 | 0.491 | 0.559 | 0 |
| New source/vector SQL write transaction | 128 | 1.861 | 2.661 | 5.113 | 19.493 | 0 |

[Fresh fixture evidence](evidence/android-memory-counts-20260912/fresh-summary.json)
contains all 31,762 samples in 28 small CSV files with independently recomputed
percentiles and outliers. The earlier 218.2ms recovered-fixture page is not
discarded just because this repeat had no >200ms backfill pages. Both use the
same metadata-only scope and no OS cache drop. This does not prove a 200ms
full-memory retrieval/write bound, strict size/latency monotonicity, or 100M capacity.

### Final shared regression and process-death repeat

The corrected APK passed all 75 shared device regressions in 550.654s, after
both million-row fixtures. The existing pinned local BGE fixture returned all
three Chinese top-one answers; 100 hot queries had P50/P95/P99 135/172/175ms.
This is a four-node fixture, not large-corpus recall or a controlled comparison.
All 192 retrieval-admission samples passed the 200ms bound (maximum 94ms).
Source paging retained 1,201 sources across 25 pages without body reads; the
complete fixture operation took 24,366ms, not a per-page UI measurement. Vector
completion retained 1,201 documents in 144,509ms. Model lifecycle checks verified
automatic indexing, three native RAG answers, and all 40 burst documents with
at most one pending worker.

The final actual process-death repeat committed counts 64/17 in PID 10288 and
terminated that process. PID 10352 independently verified the persisted cursor,
completed counts at 131/17, and compared all 148 encrypted source contents in
3.59s. Separate cleanup passed and removed only the explicitly named isolated
recovery fixture. Neither million-row database was deleted. This does not prove
physical-device reboot recovery or complete Agent Run Kernel recovery.

[Final regression evidence](evidence/android-memory-counts-20260912/final-regression.json)
records the corrected artifact, test results, all 192 admission samples and
measurement scopes. Hundred-million complete memories, full-source pagination,
streaming knowledge backup, partitioned storage and full-scale semantic recall
remain separate, uncompleted acceptance requirements.
