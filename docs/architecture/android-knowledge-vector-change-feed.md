# Durable Android Vector Change Feed

Android 1.1.73 upgrades the knowledge database from schema 4 to schema 5.
This is the source-side synchronization foundation for the native disk index,
not activation of native retrieval or a 100-million-memory acceptance result.

## Transaction Contract

- Each registered embedding model owns a random epoch and a durable head.
- A completed vector document publishes a ready event in the same transaction
  as its encrypted vector rows and authenticated completion marker.
- Source replacement and deletion publish removal events through the existing
  foreign-key cascade. The event survives deletion of the source document.
- An incomplete document never publishes a ready event. A rolled-back write
  rolls back the event, head and completed-chunk counter together.
- Removing an embedding model removes its feed. Registering it again creates a
  different epoch so a consumer cannot reuse an obsolete checkpoint.
- Sequences are global, while each event records its model's previous sequence.
  Interleaved models may have sequence gaps; a broken per-model predecessor
  chain is rejected rather than silently acknowledged.

The feed contains opaque item/model keys, ciphertext revision hashes, counts and
operations, not source text or decoded vectors. It is derived metadata, not an
authenticated authority: consumers must validate current encrypted source and
vector provenance before returning a recalled result.

## Migration and Replay

Migration adds a constant-default tracking column without a CHECK constraint or
a new index over existing documents. Write triggers validate the tracking value.
SQLite checks constraints on existing rows when adding a CHECK-constrained
column, so that form would introduce a corpus-sized migration scan.
See [SQLite ALTER TABLE](https://www.sqlite.org/lang_altertable.html).

Legacy completed documents are backfilled using the existing model/completion/key
index. Each worker transaction handles at most 64 documents by default and commits
its keyset cursor with the events. A restart resumes at that cursor. Concurrent
source replacement/deletion and newly indexed documents remain transactional.
The worker completes backfill before loading the embedding model.

Replay defaults to 128 events per page (maximum 512). These are per-operation
working-set bounds, not total memory or lifetime action limits. A future native
consumer must durably apply a page before advancing its checkpoint and may replay
the same page after interruption. Epoch mismatch, missing history and future
checkpoints are explicit errors requiring consumer rebuild.

Corpus stamps now use the durable epoch, head and chunk counter instead of
connection-local SQLite change counters. Unrelated writes no longer invalidate
the vector snapshot. Counts use the maintained counter after legacy backfill;
the existing aggregate remains a temporary fallback during backfill.

## Validation

- `KnowledgeVectorChangesDeviceTest` covers partial writes, publication failure,
  rollback, source edits/deletion, re-registration, interleaved models, small
  pages, missing events, invalid cursors, migration/resume and the UI-thread guard.
- Existing schema 1/2/3 migration fixtures remove the schema-5 additions before
  recreating their historical schema. They still verify retained source/vector
  ciphertext rather than only changing the expected version number.
- `tools/dev/test-vector-feed-host.ps1` compiles the actual Kotlin schema emitter,
  then executes its statements with Python's SQLite binding at 100, 10,000 and
  100,000 synthetic legacy documents. It checks bounded migration work, rollback,
  event ordering, counts and model-deletion cascades. This host SQL fixture is not
  Android Keystore validation or a full retrieval/write-latency benchmark.

## Remaining Work

The current App still uses its existing JVM HNSW retrieval path. JNI activation,
native node/source mapping, authenticated index generations, replay application,
consumer checkpoint acknowledgment and safe feed compaction remain separate work.
No automatic event truncation is enabled before those acknowledgment semantics
exist. Feed storage therefore grows with completed-document changes until that
consumer lifecycle is delivered. Reopening a database in a test is not proof of
device-reboot recovery, and this change makes no new ANN latency claim.
