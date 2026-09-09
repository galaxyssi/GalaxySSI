# Android Keyed FTS5 Retrieval

Android 1.1.14 (900) adds an FTS5 candidate index to the durable encrypted
knowledge database introduced in 1.1.13. It uses AndroidX
`sqlite-bundled:2.6.2`, whose SQLite build enables FTS5 independently of the
device firmware. Only this knowledge database uses the bundled driver; message,
attachment, model and runtime databases retain their existing implementations.

## Storage And Transactions

`KnowledgeSqlite` adapts prepared statements to the small operation set used by
the knowledge repository. The repository serializes access to its connection.
Foreign keys, WAL, full synchronization, parameter binding and rollback-only
nested transactions preserve the previous header/chunk snapshot contract.

FTS row IDs are mapped through a unique keyed item identity. Updates and source
replacement write the body and index in the same transaction. A before-delete
trigger removes the FTS row by indexed row ID; cascading deletion removes its
mapping and pending-backfill record. Search never opens the database through the
platform SQLite engine, which might lack FTS5.

## Privacy

Headers and body chunks retain AES-GCM encryption and authenticated metadata.
FTS receives HMAC-SHA256 tokens, not plaintext words. A separate domain-separated
token key is derived through the Android Keystore index key for each encoding
operation. The temporary derived byte array is cleared after use. Provider-owned
JVM copies cannot be guaranteed to be overwritten immediately.

Index words are NFKC-normalized and lowercased. Whole words, character trigrams,
and CJK character/bigram evidence become keyed tokens. Repeated terms in each
field are deduplicated, so BM25 operates on token presence/field length rather
than raw term frequency. Arbitrarily repeated text does not create arbitrarily
repeated index terms. Query expressions contain only quoted hexadecimal tokens.

This is a keyed searchable index, not fully oblivious searchable encryption or
whole-file SQLCipher. Token equality, occurrence relationships, document lengths,
row counts and access patterns remain visible. A local attacker able to modify
SQLite can suppress index matches; authenticated body reads reject altered
payloads but do not prove index completeness. No knowledge is uploaded to build
or search this index.

## Retrieval And Upgrade

Schema 2 migration creates the index and a persistent pending-key table without
decrypting the entire existing corpus. A single background executor backfills
eight records per transaction and yields between batches. Closing the helper
stops its work; reopening schedules remaining records. Failure leaves pending
rows intact. New writes are indexed synchronously in their own transaction.

Indexed queries retrieve up to 256 FTS candidates, with title/summary/body
weights 5/2/1, before applying the existing lexical score and top-hit limit. Until
backfill finishes, pending rows are additionally scanned so migration does not
silently hide them. Thus completed selective queries avoid whole-corpus body
decryption; pending migration can still have O(N) query cost. Broad queries and
candidate truncation require retrieval-quality evaluation, not exact equivalence
with the old full scan. Deletion retains its full matching scan and does not
delete only a truncated search result set.

This implements the FTS5 stage, not neural vector memory. Neural embeddings,
vector indexes, learned reranking, source pagination and comprehensive latency
and retrieval-quality gates remain separate unfinished work.

## Validation Plan

The new JVM tests cover CJK/supplementary characters, normalization, key isolation,
query syntax, secret-array clearing, repeated text and document evidence beyond
the query-token limit. Device tests check actual FTS5 availability, opaque stored
terms, Chinese/English retrieval, selective reads in a 1,201-record corpus,
transactional index rollback/deletion and schema-1 backfill after helper reopen.
The original 11 durable-store device tests must also pass with the bundled driver.

## Executed Evidence (2026-09-09)

- SM-T575 received Android 1.1.14 (900) through data-preserving replacement. No
  operation was performed on the connected SM-G9880.
- Final main/test APK build and 115 JVM tests across 13 suites passed, with no
  failures, errors or skips (`knowledge-fts5-final-build.log`).
- All 16 device tests passed in 276.504 seconds (`knowledge-fts5-final-device.log`).
  An earlier build also passed 16 tests before mixed-script/width normalization
  and the 100-sample hot-query gate were added.
- In a 1,201-record synthetic corpus, a unique-match query decrypted one item and
  took 54 ms. The next 100 repetitions each decrypted one item: P50 25 ms, P95
  32 ms, P99 45 ms. The P95 <500 ms device gate passed. These are selective hot
  queries, not a general search, startup, migration or production-corpus SLA.
- All 73 packaged Android AArch64 libraries passed the 16 KB alignment gate;
  all 24 QNN libraries passed the package gate. No ASR/QNN inference benchmark
  was performed by this change.
- Post-test cold activity launch was 2,582 ms, and the crash buffer was empty.
- Main APK SHA-256:
  `a51e7db5ec4e4999a9a77aed638efed863457920beb2a17fb8b04836aa18e8e3`.

The schema-upgrade test deliberately recreates the previous schema and closes
and reopens the helper during pending backfill. It does not substitute for a
physical reboot or process-death acceptance matrix. Tests use isolated data,
not user knowledge or cloud providers.

## Primary References

The next storage stage is documented in
[encrypted vector checkpoints](android-encrypted-vector-checkpoints.md). FTS5 is
still the active production ranking path; the vector ledger is not a substitute
for completing hybrid retrieval and model lifecycle integration.

- [AndroidX bundled driver](https://developer.android.com/reference/androidx/sqlite/driver/bundled/BundledSQLiteDriver)
- [AndroidX SQLite releases](https://developer.android.com/jetpack/androidx/releases/sqlite)
- [Bundled SQLite FTS5 build flag](https://android.googlesource.com/platform/frameworks/support/+/7148f22347ad3c1cd6e4672a56feb6941506cfa1/sqlite/sqlite-bundled/build.gradle)
