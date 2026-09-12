# Resumable knowledge payload compaction

This phase builds on canonical encrypted payload segments. It reclaims obsolete
bytes from partially live files without evicting valid memories, rewriting
logical source revisions or introducing a corpus-wide JSON manifest.

## Incremental live-byte accounting

Schema 12 adds a small usage row per live segment and an enrollment checkpoint.
Source-table triggers maintain live bytes and item counts in the same transaction
as insertion, reference replacement and deletion. Counter underflow, overflow,
missing accounting rows and reversed enrollment transitions abort the mutation.
Counters are derived metadata, not authentication or authorization evidence.

Opening an older database creates empty derived tables and adds a default-valued
tracking column. It does not count, rewrite or index the complete corpus. Idle
maintenance enrolls existing references with a durable 64-row keyset page. New
writes enroll immediately, including writes behind the migration cursor; deleting
an unenrolled row does not subtract from a count it never entered. Reclamation
waits until enrollment completes, so partial counters cannot determine whether
a file is disposable.

Once ready, fragmentation checks are indexed point lookups, not `SUM` scans over
every record in a segment. Actual source membership is still checked separately
before deletion. Usage rows disappear when their final live reference is removed.

## Small-record relocation

Maintenance holds the existing exclusive segment lease and a source SQLite
writer reservation. A live segment becomes eligible when at most half of its
physical bytes are referenced. A step visits at most two catalog entries by
default and moves at most eight records / 1 MiB. These are scheduling limits,
not memory-retention or agent-action limits.

The source segment is sealed before copying. Existing encrypted blocks are
authenticated and re-encrypted with the destination identity, then synced before
new references are published. Small relocated records share the existing segment
writer; they do not create one destination file for every ordinary memory.

**A transaction that relocates references never deletes the old segment.** It
commits the new references first. A later transaction, under the same lease and
writer reservation, checks durable membership and reclaims the now-unreferenced
file. If publication fails or the process dies before commit, the old reference
and its bytes remain readable. Unpublished destination bytes are reclaimed by
the same catalog mechanism.

## Large-record checkpoints

Records larger than 1 MiB of encrypted storage use the existing frame-copy engine
and a detached destination. An authenticated catalog checkpoint records copied
and verified frame offsets. Each step processes at most 1 MiB with fixed-size
buffers, commits complete frames on cooperative yield and resumes from its durable
checkpoint after reopening. Readback verification precedes reference publication.

The pending job pins its source and destination: all reclamation services a copy
job before visiting other segments. A completed job remains present until a later
transaction observes the committed destination reference. A newer user write or
deletion cancels an obsolete job without restoring old content. Catalog cleanup
never deletes files directly; subsequent membership checks decide reclamation.

Long-lived WAL exports retain shared leases and therefore defer compaction rather
than allowing old files to disappear underneath the reader. The source writer
monitor is not held for the whole export.

## Scope and validation

The implementation does not change personal-memory storage, model lifecycle,
ASR/QNN, network transport or native vector files. Schema 12 is not readable by
older schema-11 APKs; portable rollback uses logical backup/restore, not an APK
downgrade.

Tests cover usage enrollment, interleaved mutations, rollback, reference-publication
failure, snapshot lifetime, unchanged logical revisions, durable multi-step copies,
newer writes superseding a copy and corrupted checkpoints. A separate SM-T575 host
driver injects actual process death before relocation commit, after commit and
during a large-record copy. Synthetic incompressible padding tests the physical
copy engine without conflating that test with full-text-index throughput.

## Verification

The pre-integration Android 1.1.102 (988) and its instrumentation APK built successfully after fixing
one test-helper visibility declaration; production compilation was already valid.
The full JVM suite contains 3,787 cases, with zero failures/errors and five
existing skips. All 74 packaged Android AArch64 libraries passed the 16 KiB audit.
The new APK was installed in place on the designated SM-T575, without resetting
data or pairing and without operating another device.

All 20 targeted device cases passed in 28.723 seconds: five accounting cases,
six compaction cases and nine previous payload cases. The separate eight-phase
host driver also passed, including three actual process deaths and subsequent
recovery on the same retained fixture. It checks that old bytes survive a
pre-commit death, committed references survive a later death, and a partially
copied large record resumes instead of restarting or overwriting newer data.

The expanded 144-case device regression passed in 761.916 seconds, covering
knowledge identity, schema upgrades, FTS, vectors, source paging, snapshots,
streaming backup and the new physical-storage behavior. These pre-integration
results identify an exact APK hash; they do not describe the independently
published main-branch 1.1.102, which does not yet include this feature.

Latest-main integration will use Android 1.1.103 to avoid the version collision
with PR #3027, and its verification will be recorded separately. This phase does
not establish 100M-record capacity, full metadata/FTS sharding, end-to-end 200 ms
performance, low-storage coverage or device-reboot acceptance.
