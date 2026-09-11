# Paged enrollment of existing memory sources

Android 1.1.91 / knowledge schema 6. The initial candidate was measured as 1.1.90;
PR #3010 subsequently occupied that version and was merged before publication.
This is not 100M-record capacity acceptance.

## Removed unbounded work

Previously, registering an embedding model inserted every existing source key
into `knowledge_vector_queue` in one source transaction. Initial model activation
therefore copied an entire corpus before the first bounded encoding batch, even
though subsequent encoding and native replay already used pages.

Registration now creates only the model and its derived enrollment cursor. When
the pending queue is empty, `nextJob()` discovers at most 64 keys plus one
lookahead through the source primary-key index. It queues eligible keys and
advances the cursor in the same transaction. A full page of already completed
documents still counts toward that work bound: filtering happens after LIMIT,
not in an unbounded scan for the next unfinished document.

The page size is a scheduling quantum, not a memory-count or action-count cap.
There is no OFFSET, whole-corpus key list, source-body decryption, or one-shot
queue copy. The existing source-insert trigger continues to queue live changes.
There is no promise of a hard wall-time bound for an individual SQLite/fsync call.

## Consistency and recovery

- New models begin with an empty cursor and incomplete discovery. Schema-5
  models are already fully enrolled because their prior registration was atomic;
  migration marks only those models complete without scanning source rows.
- Queue insertion and cursor advancement commit together. A failed or silently
  ignored checkpoint rolls back the whole discovery page. Closing or killing a
  process cannot publish only half of that SQLite transaction.
- Source replacement/deletion uses the existing source transaction and foreign
  key cascades. Inserts behind the discovery cursor are not missed: the live
  trigger queues them. Queue conflicts keep existing work rather than replacing it.
- A source already fully indexed by live work is not queued again when discovery
  eventually reaches it. Unfinished document checkpoints are preserved.
- Queue-empty and discovery-complete are separate states. The indexer and durable
  worker request another quantum when discovery remains, without loading an
  encoder just to skip an already completed page.
- The model page labels counts as the known queue while additional sources are
  still being discovered. It does not present a temporarily empty queue as an
  exhaustive pending-document count.
- Unregistering a model cascades its enrollment state and leaves other models
  and source memories intact.

The cursor holds an opaque HMAC source key, not plaintext memory. Like the existing
SQLite queue/feed metadata, it is a derived local hint rather than an externally
authenticated checkpoint. Shape violations or a missing cursor fail explicitly;
this change does not claim protection against a privileged attacker replacing
valid SQLite metadata or rolling back the entire database. Source/vector AEAD,
revision checks and privacy boundaries remain unchanged.

## Verification coverage

- Actual encrypted-source integration: page bounds and query plan, empty stores,
  edits/deletes on both sides of the cursor, completed live sources, rollback,
  ignored updates, concurrent refills, close/reopen, v5 migration and model isolation.
- Explicit three-process recovery fixture: commit 64 entries, terminate the test
  process without cleanup, then verify the cursor, finish all 131 queued identities
  and reread all 131 original Chinese source records in a fresh process.
- Isolated directory scale ladder: 1,024 / 10,240 / 102,400 / 1,000,000 unique
  source keys. Compare the old SQL queue copy with registration and every paged
  transaction; verify each queued key and reopen in the middle and at completion.
  Retain all timing samples, including checkpoint/fsync outliers.

The scale ladder deliberately isolates directory/queue behavior. Those rows do
not contain encrypted source bodies or embeddings and must not be reported as
a million complete memories. SQL timing excludes model-key HMAC derivation,
Keystore, encoding, JNI, UI, data generation, CSV writing and verification.
It uses the bundled SQLite driver with WAL and `synchronous=FULL`; OS caches are
not dropped. Completed synthetic fixtures are retained for follow-up inspection.
Large-scale and process-termination tests require explicit instrumentation flags.

## Remaining work

The controller still computes vector/queue counts by SQL aggregation. That is
another scale-sensitive path, not made constant-time by this change. Ordinary
queued mutations can also produce a large queue; bounded initial discovery does
not cap or silently discard those mutations. Continuous new work can delay
discovery because existing queued work is processed first.

Full source/index partitioning, compressed source projections, coarse/fine vector
routing, natural OS scheduling, full UI/ASR concurrency and the real 100M+ scale
ladder remain required. The Run Kernel, full tracing and ordinary Agent DAG goals
remain active and are not satisfied by this storage change.

## Results

The first build attempt stopped before compilation because this shell lacked the
SDK environment path. After that was supplied, the default 2GiB in-process Kotlin
heap reached 2,083,348KiB used out of 2,097,152KiB. At the user's request, that
specific build daemon was stopped and the checked-in Gradle default was changed
permanently to `-Xmx8192m`. The replacement daemon was verified with that argument.
This changes host build memory, not Android runtime memory. Explicit CI 6GiB
overrides remain separate. Both interrupted build logs are retained.

### Initial candidate, before the main merge

Only SM-T575 was operated. Android 1.1.90/code 976 was installed in place, without
uninstalling or changing the original installation date. No production database,
pairing, ASR/QNN model, global Agent or self-evolution configuration was reset.
The existing BGE fixture was reused; no model was downloaded or replaced.

- The 8GiB-default build completed successfully in 831 seconds, producing the App
  APK, matching instrumentation APK and JVM unit results: 3,730 tests, zero failures
  or errors, five existing skips. All 74 packaged arm64 libraries passed 16KiB alignment.
- Device regression: 75 tests passed in 500.523 seconds. This includes all ten new
  enrollment cases, ledger/change-feed/source-paging regressions and native/hybrid
  search and worker lifecycle coverage.
- The explicit recovery test intentionally killed its process after committing 64
  queue entries. The fresh process verified all 131 queued identities and all 131
  encrypted Chinese source records in 3.929 seconds. Isolated fixture cleanup passed.
- Existing real BGE neural search: 3/3 Chinese top-one answers, 100 warm retrievals,
  P50 113ms / P95 144ms / P99 146ms. This is a four-node fixture, not large-corpus recall.
- Concurrent admission regression: 192 samples across six phases, maximum 88ms.
  These measure admission, not completed background embedding or UI rendering.

### Directory cardinality ladder

The isolated SQL test passed in 250.477 seconds. Every queued identity was checked;
each level reopened midway, and the final million-entry queue survived another
close/reopen. The retained synthetic database occupies 462,893,056 bytes, including
free pages reused after the old eager-copy comparison; it is not a memory-size forecast.

| Source keys | Old eager register (ms) | New register (ms) | Pages | Page P95 (ms) | Page P99 (ms) | Page max (ms) |
| --- | --- | --- | --- | --- | --- | --- |
| 1,024 | 18.519 | 2.577 | 16 | 14.354 | 14.354 | 14.354 |
| 10,240 | 98.043 | 2.116 | 160 | 15.681 | 19.371 | 24.532 |
| 102,400 | 1,005.972 | 0.885 | 1,600 | 14.427 | 20.199 | 39.921 |
| 1,000,000 | 7,292.787 | 2.210 | 15,625 | 16.521 | 26.637 | 172.586 |

All 17,401 page transactions were below 200ms in this run. Registration now defers
discovery: the 2.210ms figure does not mean all million keys were processed in that
time. There is no hard latency guarantee or monotonic per-operation speed claim.
The eager comparison runs first, warms caches and makes freed database pages
available. New registration is one transaction per level, not a percentile sample.

[Machine-readable results and all page samples](evidence/android-memory-enrollment-20260912/summary.json)
retain the original candidate version and APK hash. Raw CSV files are split into
at most 1,500 samples per file; runtime source storage does not use these JSON/CSV files.

### Merged candidate

Latest main `f2a656403` (including PR #3010) was merged without replacing its UI,
evidence preview or clock changes. Android advances to 1.1.91/code 977.

- The merged App APK, matching test APK and JVM tests built successfully in 603
  seconds with the checked-in 8GiB default, without a command-line heap override.
- 537 JVM suites contained 3,750 tests: zero failures/errors, five existing skips.
- Repository guard passed; all 74 arm64 native libraries passed 16KiB alignment.
- Installed in place on SM-T575; version 1.1.91/code 977 and the unchanged original
  installation date were confirmed from the package manager.
- Final merged APK SHA-256:
  `c60e9065df7a9854b21ff3459a77f7d870a6de7d0f60212789850bbcdcd369fb`.
- All 22 focused merged-version enrollment/ledger device regressions passed in
  150.539 seconds, including the 1,201-document completion regression. The full
  million-key timing ladder above remains labeled with its original 1.1.90 APK.
