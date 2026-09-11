# Paged enrollment of existing memory sources

Candidate Android 1.1.90 / knowledge schema 6. Validation is pending until the
device results below are recorded. This is not 100M-record capacity acceptance.

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

## Verification plan

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

Pending candidate build, device regression, recovery and directory scale results.
