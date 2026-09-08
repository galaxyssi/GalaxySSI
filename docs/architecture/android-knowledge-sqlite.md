# Android Durable Knowledge Storage

For the subsequent FTS5 candidate-index stage, see
[Android Keyed FTS5 Retrieval](android-knowledge-fts5.md). The observations below
describe the original 1.1.13 storage delivery.

Android 1.1.13 (899) routes the existing knowledge-store facade to SQLite. The
old class name remains as a delegating API so the importer, native Agent actions,
RAG access checks and ordinary Agent context use the same storage path.

## Persistence

Previously each update decrypted and rewrote one array and retained only its last
500 items. This implementation has no storage-count eviction. Upsert touches the
matching item/title records; source replacement is transactional. Access-policy
updates and deletions preserve the existing mutation-event integration. A source
replacement cannot overwrite an ID belonging to another source.

Bodies and headers use the existing Android Keystore AES-GCM cipher. Long JSON
items are split into 16 Ki UTF-16 chunks, preserving surrogate pairs. Each chunk
is authenticated with its database/item/ordinal identity. Headers authenticate
chunk count, content digest and indexed metadata. Missing, changed or reordered
data is reported, not treated as an empty knowledge store.

ID, title and source lookup values are HMAC-SHA256 tokens from a separate Android
Keystore key, not plaintext or publicly guessable unsalted content hashes. SQLite
still exposes counts, timestamps, row sizes and equality patterns. This is
application-level encrypted payload storage, not whole-file SQLCipher encryption.
No persistent plaintext title, body, source or vector table is introduced.

## Migration And Backup

Migration validates every legacy item and stable ID, writes and reads back the
complete dataset in a single transaction, then records the migration marker.
Only after commit does it remove the legacy array. Decryption/parse/write errors
retain the old copy and do not commit an empty migration. Unrelated preferences
are untouched. Mutation observers are not fired for migration.

Encrypted application backup now exports from SQLite and restores transactionally
without the old 500-item and 20,000-character truncation. JSON backup serialization
still materializes the export array; a streaming backup format remains future
work. System Android backup remains governed by the existing application manifest.

## Retrieval Boundaries

This is the durable storage stage of Memory 2.0, not completed vector memory.
Existing lexical/substring/trigram ranking is retained. Ranked search reads
64-key pages and retains at most the requested top candidates, rather than caching
the entire knowledge array. It is still an O(N) lexical scan; FTS5, neural
embeddings, vector indexing, reranking and their real retrieval-quality/latency
acceptance remain to be integrated. Search result limits are not storage limits.

The database snapshot transaction keeps each header/body read consistent with
concurrent mutations. This serializes current store operations and must be
considered when replacing scans with indexed retrieval. UI source grouping and
global-context callers still have their own list limits and need paginated
presentation work; removing storage eviction does not make those views unlimited.

## Validation Coverage

Device tests exercise 1,201 retained items and reopening; policy-preserving legacy
migration; malformed and undecryptable legacy input; large Unicode chunking;
transaction rollback; access updates; source replacement; chunk deletion;
601-item backup roundtrip; invalid backup rollback; and altered index metadata.
They use isolated test databases and preferences, not user knowledge.

## Executed Validation (2026-09-09)

- Target: SM-T575; Android package 1.1.13 (899), installed with data-preserving
  replacement. The connected SM-G9880 was not operated on.
- `AgentKnowledgeDatabaseDeviceTest`: 11 passed, no skips, 90.142 seconds.
  The 1,201-item check closes and reopens the SQLite helper; it is not a device
  reboot or process-death acceptance test.
- Knowledge, memory and private-data-inventory JVM filters: 107 passed across
  12 suites, zero failures/errors/skips.
- Main and instrumentation APK builds passed, as did `npm run check`, the
  72-library Android 16 KB audit and 24-library QNN package audit.
- Post-test cold activity launch: 2,567 ms; crash log buffer was empty. This is
  a single launch observation, not a P95 benchmark or an ASR/QNN performance test.
- APK SHA-256:
  `2f00b5a8e7bf270f26564518493e2925cf499f8f44ce54cb2b7b98e7321c65d9`.

Evidence logs in the local build directory are `knowledge-sqlite-verified-build.log`,
`knowledge-sqlite-device.log`, `knowledge-sqlite-repo-check.log`,
`knowledge-sqlite-16kb.log` and `knowledge-sqlite-qnn.log`. An earlier intermediate
build failed against stale compiled API classes; the final builds and installed
APK above include the backup methods and blank-query result-limit regression.

After merging latest main `2a1b7039b` (PR #2915), APK builds and repository
checks passed again. The main APK hash was unchanged. The rebuilt instrumentation
package repeated all 11 tests successfully on SM-T575 in 91.281 seconds, with no
skips (`knowledge-sqlite-merged-device.log`). Merged-base build/check logs are
`knowledge-sqlite-merged-build.log` and `knowledge-sqlite-merged-check.log`.
