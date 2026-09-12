# Encrypted knowledge payload segments

This phase separates canonical knowledge bodies from the metadata SQLite file.
It reuses the existing compressed record framing and authenticated append-only
segment engine, without changing personal-memory payloads, native vector files,
model lifecycle, ASR/QNN, or the network protocol.

## Publication and reads

Knowledge schema 11 adds a reference/membership table and a physical migration
cursor. New bodies of at least 8,192 UTF-16 code units are externalized; smaller
records remain inline until the indexed live-item count reaches 16,384. These
are storage-layout thresholds, not retention limits. No records are evicted.

The segment writer compresses independent 64 KiB blocks and encrypts them with
the existing Android Keystore AES-GCM key. Associated data includes database,
item, segment, record, offset and block identity. Files rotate at a 64 MiB target
and use UUID filenames under two-hex-digit directory prefixes. An individual
record may exceed the rotation target; it is not truncated or rejected for that
reason. This segment format uses neither corpus-wide JSON nor an in-memory
manifest. Explicit legacy JSON export adapters elsewhere are not removed by
this phase; production streaming backup remains the scalable export path.

Publication order is:

1. Acquire shared segment access before the source SQLite transaction.
2. Durably register a new segment in the separate paged catalog if necessary.
3. Append and fsync all encrypted payload blocks.
4. Encrypt the bounded reference and insert its membership in the source
   transaction, together with header, FTS and source/vector bookkeeping.
5. Commit source SQLite before releasing shared access.

A rollback or process death before step 5 leaves the original source readable;
unpublished bytes remain reclaimable. A committed reference never intentionally
points to bytes that have not been synced. Reads authenticate both the reference
and block identities, then check the existing header content hash. Missing,
corrupt or substituted payloads fail explicitly rather than becoming empty hits.
Older binaries that only support schema 10 cannot open schema 11. Downgrading
the APK is not a supported storage rollback; logical backups remain the portable
restore path and are re-encrypted in the destination namespace.

The current API still decodes one complete item to an object. Memory use is
bounded by a single item plus framing buffers, not by the whole corpus; a very
large individual item is still a separate memory-risk area.

## Snapshot-safe lifetime

Both source projection and backup retain pinned WAL read snapshots. Each now
also retains a shared segment lease until close. Leases allow another thread or
process to publish new data while old data is exported. They are reference-counted
within the process and backed by an OS file lock across processes. They do not
hold the source writer monitor for the lifetime of an export.

Reclamation requires an exclusive lease plus a SQLite writer reservation before
checking committed membership. It yields while a live snapshot or unpublished
append holds a shared lease. OS process death releases file locks; recovery does
not depend on manually deleting stale lock files. Closing an owner invalidates
its snapshot API but does not release the snapshot's lease prematurely.

## Migration and maintenance

Schema creation adds empty metadata only. It does not copy all bodies at open.
Idle WorkManager maintenance walks a durable keyset cursor, four records per
transaction by default. The checkpoint, new reference and removal of old inline
chunks commit together. The header and logical source revision do not change,
so migration does not invalidate FTS, native vectors or source projections.
When the scheduling quantum expires after completed records, the completed
prefix and its cursor are committed. A slow record is not repeatedly discarded
only because it took longer than a scheduling quantum. Other exceptions roll
back the current page; prior committed pages remain intact.

When the corpus crosses the large-store threshold, the migration cursor starts
one further sweep to externalize remaining small rows. Live writes already use
the external layout. The worker shares the existing five-second scheduling
quantum and yields in the foreground; this is not a task or memory-count limit.
Failures retain the current checkpoint for a later attempt.

The catalog is paged; maintenance visits two segment registrations per step and
reclaims completely unreferenced files. Partial live-segment compaction remains
to be integrated with snapshot-safe relocation. Deleting a record removes its
live database reference immediately, but does not promise immediate physical
erasure of its encrypted bytes from a partially live segment.

## Acceptance boundaries

This is physical value separation, not complete canonical metadata/index
partitioning. Source headers, memberships, FTS and replay indexes remain in one
WAL database. Full 100M capacity, end-to-end 200 ms performance, arbitrary large
item decoding, partial-segment compaction, low-storage fault matrices and device
reboot behavior remain distinct acceptance requirements.

## Verification

On the designated SM-T575, the pre-integration Android 1.1.101 (987) build passed
all 133 knowledge instrumentation cases in 807.132 seconds. Coverage includes
payload corruption, atomic reference publication, rollback, bounded migration,
concurrent writer/snapshot lifetimes, streaming backup, source projections, FTS,
vector bookkeeping, schema upgrades and indexed stats. A targeted nine-case
payload run also passed independently in 9.731 seconds.

Three deliberate process deaths verified pre-commit rollback, post-commit
durability and reclamation after a process died while holding a snapshot lease.
The same isolated recovery database was reopened after each death; no production
database or pairing was reset. An initial test-only whitespace expectation was
corrected before these successful death/recovery phases. A broader first run
also exposed five legacy-schema fixtures that retained the new tables while
pretending to be older schemas. The shared fixture downgrade helper now refuses
to discard live payload references and removes only empty synthetic tables.
The final 133-case rerun includes all five previously failing cases.

The pre-integration JVM suite contained 3,783 tests, with zero failures/errors
and five existing skips. After integrating main `cef237557` (including PR
#3025), the rebuilt App and test APK succeeded in 494 seconds. The integrated
JVM suite contains 3,787 tests, again with zero failures/errors and five existing
skips. All 74 packaged Android AArch64 libraries passed the 16 KiB ELF/ZIP audit.
Rebuilt artifact hashes and integrated device results are recorded separately
in the evidence summary. These are correctness and recovery tests, not a
100M-record capacity or latency benchmark.

The integrated APK was installed in place on SM-T575, preserving user data and
all older isolated fixtures. Its 44 focused device cases passed in 412.574
seconds. A fresh isolated fixture then completed all seven host-driven phases,
including three deliberate process deaths and all recovery assertions. The
older successful recovery fixture was retained as well. Device reboot, UI
latency, real-provider calls and other devices were not part of this run.

See [the evidence summary](evidence/knowledge-payload-segments-20260912/summary.json)
for artifact identities and separate pre-integration/integrated results. Raw
instrumentation evidence is split by class, with each file below 30 KB and
1,500 lines. Reproduce the device cases with the named instrumentation classes
and the explicit SM-T575 serial; process-death checks use
`tools/dev/test-knowledge-payload-recovery.ps1` and never use production rows.
