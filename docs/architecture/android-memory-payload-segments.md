# Android encrypted personal-memory payload segments

Status: implementation in progress. Not a 100M-capacity, native ANN, or latency
acceptance claim. Do not publish this stage as completed before the recovery,
reclamation, and production-path checks below.

## Production path

`AgentPersonalMemoryRows` still owns memory identity, revisions, lookup membership,
browse/recall index updates, and source transactions. `AgentEncryptedDatabase`
can now separate a personal row's payload from its SQLite commit reference.
Other component keys and databases retain their existing inline encoding.

Small personal rows remain inline. A row of at least 8,192 UTF-16 characters is
eligible for an external payload. Once the source metadata counts at least
16,384 records, normal remember/flag/access writes externalize the affected
personal rows, including short ones. This threshold selects a storage layout;
it does not remove memories, limit the total count, or truncate a query.
Existing inline rows are readable without migration, and updates touch only
their targets. An initial bulk import can still leave short rows inline; a
resumable cold-row migration is not implemented in this stage yet.

The segment root is adjacent to the physical database, with UUID file names and
two-hex-digit directory fanout. References address one file/range directly;
there is no whole-corpus JSON manifest or startup file enumeration. A process
starts a new segment instead of guessing whether another process's old tail is
complete. A writer rotates before the next record after its current file reaches
the 64MiB target. One oversized record may exceed that target; it is not split
across files or silently rejected. Offsets, lengths and block counts use checked
64-bit arithmetic.

## Durability and privacy

The already tested backup record codec provides bounded 64KiB compression and
record framing. The framed stream is encrypted in independently authenticated
64KiB-or-smaller AES-256-GCM blocks using the Android Keystore storage key. No
plaintext intermediate file or whole-corpus plaintext cache is created. The
current String-based source API still materializes one record, not the corpus;
this is not a constant-memory API for an arbitrarily large single record.

Block AAD binds database/item identity, segment, record generation, offset and
block ordinal. SQLite stores a separately authenticated, fixed-size reference
that binds the final length, plaintext byte count and block count. Missing files,
partial blocks, changed tags, swapped identities, incomplete consumer reads and
bad lengths fail explicitly, not as an empty/default memory.

The commit order is:

1. Create the new segment/directory if needed and sync its directory entries.
2. Append bounded encrypted frames and sync the file descriptor.
3. Encrypt the final reference.
4. Commit the reference and derived indexes in the existing SQLite transaction.

SQL rollback leaves the earlier reference/indexes unchanged. A crash before
reference publication can leave unreachable ciphertext, not an acknowledged
reference to unsynced bytes. File sync and directory sync are separate operations;
this follows the [fsync contract](https://man7.org/linux/man-pages/man2/fsync.2.html).
Durability still depends on the OS/filesystem honoring sync and on SQLite's
durable configuration; it cannot overcome broken hardware flush semantics.
See [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html).

The storage is not oblivious: file counts, sizes, update frequency and access
patterns remain observable. Logical deletion is not physical flash erasure or
per-record cryptographic erasure. Shared Keystore key handles and Java charset/
cipher internals are not claimed to be completely zeroizable.

## Required before release

- Run JVM framing/authentication tests and real Keystore/SQLite device tests.
- Verify streaming backup/restore, mixed inline/external browse, recall and
  deletion barriers without changing their semantics.
- Complete bounded reclamation/compaction of obsolete and orphan payloads.
  Current append-only files retain old revisions after row replacement/deletion;
  repeated writes must not cause permanent unbounded garbage growth.
- Verify actual process interruption between durable append and SQL publication,
  restart after publication, low storage and injected corruption.
- Measure write/read/space costs at real cardinalities, including threshold
  crossing and cold-row migration. The earlier accepted 800-sample inline result
  does not certify this new layout.
- Add native disk vector retrieval and routed/sharded lexical catalogs. SQLite
  metadata/indexes remain in one database; payload segmentation alone is not
  complete sharded memory or 100M search.

No ASR/QNN model lifecycle, cloud routing, pairing, or native library is changed
by this implementation.

## Development evidence (2026-09-11)

- A focused host compilation using the repository's Kotlin 2.0.21 compiler ran
  `MemorySegmentFileTest` and `BackupRecordStreamTest`: **23 passed**, 2.678s.
  These use real JCA AES-GCM, but the host directory-sync callback is instrumented;
  they do not certify Android Keystore or power-loss persistence. Logs:
  `build/memory-segments-host-compile.log` and
  `build/memory-segments-host-tests.log`.
- Repository checks passed. The first Android build found that `O_DIRECTORY`
  is not a public Android SDK constant; the adapter now opens read-only, verifies
  `fstat` reports a directory, then syncs it. No magic Linux flag is hard-coded.
- The corrected build generated the candidate APK and instrumentation APK in
  14m14s (`build/memory-segments-v1169-build-retry.log`). Its Gradle-targeted
  tests passed the same 23 cases; this is a second execution, not 46 unique tests.
- The subsequent full JVM regression passed **3,650 tests**, with five existing
  skips, zero failures/errors, out of 3,655 discovered tests. Android test sources
  also compiled. Log: `build/memory-segments-v1169-regressions.log` (4m13s).
- Candidate APK SHA-256:
  `62adeff3d1c3939daed2f22ae4acf2bc132fac3a4acf452999a5f04ba603860d`.
- Device tests for the real storage entry points are added but not yet executed.
  SM-T575 was read-only checked at **1.1.68 (954)**; no new APK has been installed
  during this stage. Source version **1.1.69 (955)** is a development candidate.
- No PR has been published for this incomplete segment stage. Reclamation,
  recovery and real performance remain release gates, not deferred acceptance.
