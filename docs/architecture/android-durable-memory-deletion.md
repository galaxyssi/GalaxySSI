# Durable personal-memory deletion

## Storage and transaction boundary

Android 1.1.57 stores personal-memory deletion records in the same encrypted
SQLite database as personal-memory items (`galaxyssi_agent_memory_v2`). Each
record has its own `memory-deletion:v2:record:<content hash>` key. Record values
use the existing Android Keystore AES-GCM envelope with database/key AAD.

Deleting memory commits the updated item array and its deletion record in one
`AgentEncryptedDatabase.mutateStrings` transaction. The decoded item cache is
updated only after the transaction succeeds. Failure no longer requires a
second compensating write that could itself fail or be interrupted.

Memory stores, deletion indexes and the memory part of backup restore share the
same process lock. Backup export captures the memory array and deletion records
under that lock. Restore validates incoming deletion records, combines their
causal filters with local records, and commits filtered memory plus incoming
deletion records together. Restoring a deletion-only backup also filters the
current memory state.

This transaction boundary does not cover other backup domains such as tasks,
contacts, workflow settings, or the global world model.

## Migration and integrity

The old `galaxyssi_agent_memory_deletions_v1` encrypted array is validated and
copied into individual records. The migration marker commits in the same
transaction as the copied records. The old encrypted source is retained rather
than deleted across a two-database boundary. Migration is idempotent.

New storage does not truncate at 2,000 deletion records. The codec no longer
truncates memory IDs/fingerprints at 1,000 or retractions at 2,000; every field
must survive the content-hash check. Invalid records, unreadable ciphertext,
invalid migration markers, malformed arrays, and mismatched record IDs fail
explicitly. They are not treated as an empty deletion history during restore.

Restore also rejects malformed top-level memory/deletion fields, missing/blank
memory IDs or values, and duplicate IDs before writing the replacement memory
array. An absent field and a present field with the wrong type are not treated
as equivalent. Legacy records with no scope use the same
GLOBAL default as the existing memory decoder, so suppression cannot be bypassed
by omitting that field.

Historical deletion records already evicted by older releases cannot be
reconstructed from the remaining ledger. Available valid records are migrated
without dropping more history.

## Scale and backup

- Appending a record does not read or rewrite existing records.
- Internal scans use keyset pages of 128 keys. This is an I/O page size, not a
  total-record limit.
- Restore builds a suppression index of deleted IDs and latest deletion times
  per fingerprint, then scans the supplied memory array once.
- Retraction publication reads bounded pages and releases the memory lock
  before calling the global repository.
- Explicit full snapshots/JSON exports still materialize their requested
  result. The personal-memory item store itself remains a serialized array;
  this change is not a fully paged replacement for that store.
- Personal-memory backup no longer silently keeps only 200 records or skips
  values over 24,000 characters. Workflow backup limits are unchanged.
- The 1,000 survivors in the reboot fixture are a test outcome, not a storage
  limit. Existing `trimHistory` retains all non-SUPERSEDED memories and fills
  the remaining slots of a 1,000-item budget with recent SUPERSEDED versions.
  Non-SUPERSEDED memory can exceed that budget; historical-version retention
  remains capped. Query recall still returns at most eight items per request.

## UI execution

The memory settings page loads snapshots and usage counts on a dedicated serial
I/O worker. Its parent page loads the memory summary asynchronously. Edits,
deletions, conflict resolution, pinning and privacy changes use the same worker.
Existing navigation generation checks discard stale UI callbacks after leaving
the page; a completed operation does not navigate the user back to an old page.

The page still renders its active rows into the existing layout. Offloading I/O
does not establish a paged UI or an end-to-end frame-time guarantee. Worker tests
check that a blocked storage lock leaves the main looper responsive and that
mutations retain submission order.

## Acceptance coverage

- Codec round-trip beyond all previous array limits, retention beyond 2,000
  records, strict malformed-input rejection, and a 10,000-item suppression case.
- Isolated-device tests for migration, concurrent append, deletion rollback,
  consistent export, backup restore beyond 200 records, long values, and
  corruption that must not replace existing memory.
- A persistent device fixture starts with 2,501 memories, deletes 1,501, and
  retains 2,106 deletion records. Verification after a real device reboot must
  retain the 1,000 survivors and reject restoration of deleted records. The
  original encrypted fixture is retained for repeat inspection.

The device suite calls the actual `AgentBackupData.export` and production memory
restore helpers. It does not run the entire multi-domain backup restore or
activate global/evolution scheduling. SQLite triggers inject transaction aborts;
the real reboot occurs after committed fixture creation, not during a write.

## Verified build (2026-09-10)

- Android 1.1.57 (943), SM-T575 `R52R90282TY`; Desktop is unchanged.
- Final `testDebugUnitTest`, `assembleDebug`, and `assembleDebugAndroidTest`
  succeeded in 6m 58s. JVM results: 3,541 tests, 508 suites, zero failures/errors,
  five skips. The new scale suite has ten passes and no skips.
- Final memory device run: 25 passes, zero failures/skips, 102.259s. This covers
  transaction rollback, retained legacy data, ciphertext corruption, concurrent
  append/export, backup count/value preservation, strict restore input, UI I/O
  isolation, and the earlier scoped-identity regressions.
- Final image, original-attachment, action/model timing and journal regression
  run: 22 passes, zero failures/skips, 16.805s. Missing-model tests do not prove
  successful local-model load performance.
- Persistent reboot case `20260910-v1157`: preparation passed in 39.023s before
  reboot. The original 2,501 memories and 2,106 deletion records were not reseeded.
  Boot ID changed from `efeac09c-38a4-4a75-9858-e836a08923df` to
  `a04da34f-f384-4ebd-a974-9b7d6cbd0b2d`. Initial post-reboot verification passed
  in 58.396s. After final package installation, the same fixture passed again
  in 36.171s: exactly 1,000 survivors, all deletion records retained, and deleted
  data suppressed when restoring the old memory array. These are multi-scan
  test durations, not startup or task-recovery latency measurements.
- Repository guard, 73-library Android 16 KB audit, and 24-library QNN package
  audit passed. QNN libraries total 221.68 MiB uncompressed; no model/runtime
  configuration was changed.
- Final APK SHA-256:
  `3187EDDA6DE2D82263FFC254586EA0CED8B384088066A4FE3C9325B3C5AD77D1`.
- Final update time: device local 2026-09-10 18:14:47. Original installation time
  2026-09-07 07:17:23 was retained. No app data was cleared or device re-paired.

Local logs: `build/memory-deletion-ledger-release-build.log`,
`build/memory-deletion-ledger-release-device.log`,
`build/memory-deletion-ledger-release-regression.log`,
`build/memory-deletion-ledger-reboot-prepare.log`,
`build/memory-deletion-ledger-reboot-final.log`, and
`build/memory-deletion-ledger-release-{repo,16kb,qnn}.log`.

## Remaining work

The full Memory 2.0 goal is still incomplete. The subsequent
[durable retraction outbox](android-memory-retraction-outbox.md) closes the
commit-to-publication gap and verifies storage recovery after a device reboot;
full production derived-memory projection replay remains unverified. Neither
change activates global/evolution processing. Neural reranking,
complete retrieval authorization, conflict/forgetting policy, full personal-store
paging, and comprehensive fault/backup acceptance remain separate work.
