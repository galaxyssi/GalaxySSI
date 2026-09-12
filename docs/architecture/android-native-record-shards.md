# Native source and provenance record shards

## Scope

Android 1.1.99 / native memory 0.6.0 partitions replay checkpoints, document
visibility state and node provenance across the existing physical SQLite node
shards. Previously those records accumulated in `catalog.sqlite.index_records`,
even though graph nodes already had physical shards.

This advances the 100M-memory architecture; it does not establish 100M capacity
or a universal 200ms latency bound. The authoritative Android source database,
hierarchical index routing, topology growth and large-scale acceptance remain
separate work. There is no new memory-count limit.

## Storage and queries

- New indexes create `index_records` in every existing node shard. The catalog
  retains an empty legacy table and the small encrypted `index_state` row.
- Persisted FNV-1a over the complete opaque key chooses exactly one shard.
  Its power-of-two topology is authenticated in the index metadata. Point reads
  use the `WITHOUT ROWID` primary key, not a scan or all-shard query.
- Existing AES-GCM record envelopes remain bound to the index instance, logical
  key and record revision. Physical relocation preserves their ciphertext.
- The aggregate pager and transaction-local node cache budget does not increase
  with record count. No plaintext memory map, whole-index JSON or corpus cache
  is introduced. The migration page holds at most 256 bounded record envelopes;
  the Android worker requests only 64 records per slice.
- Graph mutations, source visibility, replay cursor updates and migration share
  the existing attached SQLite transaction. Rollback journals and `EXTRA`
  synchronization are retained; this store must not be switched to WAL.

## Upgrade and recovery

The sealed metadata format `GSAN0002` authenticates a three-state record layout:
legacy, migrating or sharded. The preceding `GSAN0001` envelope decodes as
legacy. Opening only validates metadata, the root and expected table presence;
it never scans records, starts migration or rebuilds the graph.

The first background slice creates record tables in the attached shard files.
Each slice selects a bounded primary-key page from the remaining legacy rows,
authenticates each envelope, inserts it into its destination and deletes the
legacy row. The layout marker and all moves commit together. The legacy table
itself is the durable remaining-work set, so no separate unbounded manifest or
offset scan is necessary. Completion uses an indexed existence check.

During migration, reads check the destination and legacy table. Two copies of
the same key are an error, not an arbitrary winner. Updates authenticate an old
legacy value before removing it and publishing its replacement in the shard.
An insertion conflict, invalid envelope, cancellation or SQL failure poisons
the transaction and rolls back the complete slice. Missing expected tables do
not become empty memory. After completion, reads no longer fall back to legacy
rows. Old binaries cannot open the new metadata format; rollback would require
a separately designed downgrade, not silently opening the new files.

The App's durable vector worker and existing background index scheduler both
call `KnowledgeNativeIndex.advance`. A pending migration keeps scheduling
bounded successors even when source replay is already current. Ready searches
can keep using the committed graph and only schedule maintenance in the
background. Privacy cancellation, lifecycle cleanup and final authoritative
source validation remain unchanged. No inference model is loaded for migration.

## Validation

The SM-T575 native SQLite suite passed 37 tests with zero failures and one
intentional child-process helper ignored by the top-level runner. The suite
invokes that helper for real process-exit tests. Runtime was 43.80 seconds.

New coverage includes:

- 1,024 records spread over all four shards, with primary-key search plans.
- A 513-record old-format fixture resumed across nine 64-record pages and
  repeated store reopening, with every payload checked after every page.
- No migration or catalog rewrite from opening and reading an old index.
- Updates to migrated and unmigrated records in one transaction, plus rollback.
- A corrupt late-page record rolling back earlier moves and newly created tables.
- Duplicate rows, missing partition tables, invalid page sizes, read-only calls
  and cancellation before commit.
- Child-process exit before and after a 64-record migration commit, followed by
  full recovery and comparison of all 513 records.
- Migration interleaved with a partially applied graph event, duplicate append,
  source removal and reopening, preserving node count and stale-result filtering.

Native test executable SHA-256:
`528c3a48688f694aa22dcc5d4894bfa3f9ce744dc7ab76722ff5ad47f3485450`.
All four ELF LOAD segments passed 16KiB alignment verification.

The full Android debug App, instrumentation APK and JVM build passed in 13m20s.
The JVM report contains 3,779 tests in 541 suites, zero failures/errors and five
existing skips. All 74 bundled ARM64 libraries passed the 16KiB alignment gate.
App 1.1.99 (985) was installed in place on SM-T575 only, without resetting data.

The initial App instrumentation suite passed 15 tests in 31.464 seconds:
`KnowledgeNativeRecordMigrationDeviceTest`, `KnowledgeNativeBridgeDeviceTest`,
`KnowledgeNativeIndexDeviceTest` and `KnowledgeRetrievalAdmissionDeviceTest`.
It includes an 81-record legacy catalog migrated through actual JNI calls with
reopening between batches, plus query admission, source replay and lifecycle
regressions. Full logs are in
[the evidence directory](evidence/native-record-shards-20260912/).

The final rerun passed all 16 App tests in 51.985 seconds after adding a
production `KnowledgeNativeIndex.advance` regression: 80 source documents, 80
vectors and a replay cursor are downgraded to a test-only authenticated legacy
layout. A ready graph remains queryable while three migration slices finish,
including reopening between slices. The test checks all 80 search results,
unchanged graph node count and source stamp, and maintenance completion.
The supplementary instrumentation APK build passed in 2m24s; the installed
App APK hash remained unchanged. The helper only accesses its isolated test
database and test-generated Keystore-wrapped index key.

App APK SHA-256:
`3e73bbaf3fb6c73905d04f8364d36404fdcf5f2927fa3bc58e56d58e99f21a2a`.

Final instrumentation APK SHA-256:
`191446273d364fd14d79b1b4d1cce6152d87b9f82a411c3e10d0b94bf6c42a66`.

These synthetic fixtures do not prove 100M scale, memory peaks, a sustained
200ms percentile, or every real-user lifecycle path. Before installation,
SM-T575 reported 1,902,796KiB available RAM and 40,184,108KiB available storage;
those are baselines, not peak measurements. No models, retained stress fixtures
or production conversation databases were replaced or cleared.
