# Durable primary copy checkpoints

Android 1.1.114 extends primary-body partition compaction with an authenticated,
per-frame copy checkpoint. This is a follow-up to schema 15, not a replacement
body store and not acceptance of the 100-million-record goal.

## State and ownership

Schema 16 creates one persistent copy job for the active compaction source.
It records the exact authenticated original reference and a destination partition.
The encrypted checkpoint contains the entry ID, copied and independently verified
frame counts, decoded character counts, ciphertext byte accounting and two SHA-256
hash chains. Checkpoint AAD binds the namespace, item, source, destination and
original reference. It contains no plaintext memory body.

Foreign keys pin both registered partitions. The job deliberately does not cascade
with item deletion: the next maintenance step must notice a replacement or deletion,
discard the unpublished destination and preserve the user's latest state. There
is one job because the existing cross-process exclusive maintenance lease and
catalog transaction serialize physical reclamation.

## Bounded work

Records containing at most 16 frames keep the small-record fast path, with at most
eight records per maintenance page. A frame has at most 16,384 UTF-16 code units.
Large records get a dedicated sealed destination, never a normal active bucket.
Copying and verification each process at most 16 frames per page with keyset
queries. Completed frames can be committed when a cooperative yield is requested;
a hard cancellation, failed authentication or I/O error rolls back the page.
Normal reads, writes, logical revisions, FTS and vector documents are unchanged.

The destination is verified separately after copying. Frame authentication,
contiguous ordinals, bounded decoding, final character counts and a matching
source/destination hash chain are required before publishing its reference.
Publication compares the original reference and requires exactly one affected row.
An ignored or stale update must fail rather than retire a still-live source.

## Ordering and recovery

1. Register the sealed destination and copy job in the catalog.
2. Copy a bounded page into a destination transaction.
3. Commit destination frames with EXTRA synchronization before the catalog checkpoint
   (Android 1.1.117 and later; earlier versions used FULL).
4. On replay, delete only the job entry's unpublished tail at or after its durable
   copied cursor, then copy that page again.
5. Verify destination pages and persist the independent verification cursor.
6. Publish the fully verified reference and remove the job in one catalog commit.
7. Retire the empty source transactionally; unlink through the existing durable queue.

A physical commit followed by catalog rollback leaves an unpublished tail, not a
partially visible record. A process death after publication leaves a complete,
durable destination. Old references remain readable throughout copy and verification.

## Verification and limits

`tools/dev/test-knowledge-primary-copy.ps1` supports focused and real process-death
tests on the designated SM-T575. It retains test databases and verifies durable
phase markers. The existing primary, compaction, historical-schema and retained
corpus suites remain applicable. Measured results are recorded separately.

These work-page limits are not total record limits or a hard 200 ms guarantee.
One frame can still wait for device I/O, and the exclusive maintenance lease can
briefly defer readers. Normal complete-record reads still materialize that record;
the catalog, FTS and vector-control tables are not yet physically sharded. Initial
destination creation can leave an unregistered orphan if its catalog transaction
never commits. Unknown orphan discovery, long-cycle worker scheduling acceptance
and a 100-million-real-record benchmark remain unfinished.

## SM-T575 results

Android 1.1.114 (1000) was installed without uninstalling or resetting data.
All 12 focused copy tests, 10 existing compaction tests and 15 existing primary
tests passed. Seven intentional process deaths were verified with durable markers,
with seven successful preparation/recovery assertions. The longest new focused
record contains 655,361 UTF-16 code units in 41 frames; the process-death fixture
contains 21 frames. This verifies bounded progress, not maximum-record capacity.

The initial focused invocation did not execute its cases: one expression-bodied
Kotlin test inferred an exception return type, which JUnit rejects. Giving the
method an explicit Unit return type corrected the test definition. The production
APK was unchanged. The initial failure is retained alongside the successful rerun.

All 95 historical-format, encryption, source paging and vector regressions passed
in 588.507 seconds. The retained 10,001-real-record corpus passed complete encoded
record digest checks before and after reopening in 110.672 seconds. Its digest
remained `6645e346b67a5f09c6a9e4c84d292a936a1147f778ab83f94df69199e8aaa431`.
There was no newly eligible compaction work: one 6.031 ms maintenance page moved
zero records, and the physical directory remained 7,168,000 bytes. This is not a
fresh 10,001-record compaction throughput measurement.

The subsequent durable API test passed all 300 samples within 200 ms:

| Operation | Samples | P95 | Maximum |
| --- | ---: | ---: | ---: |
| Public read | 100 | 12.046 ms | 135.851 ms |
| Individually committed upsert | 100 | 74.394 ms | 126.705 ms |
| Individually committed restore | 100 | 70.253 ms | 88.502 ms |

All 100 probe records were restored and verified after reopening. These warm-store
measurements include durable write commits but exclude observers, models, UI and
network work; they do not measure maintenance contention or 100 million records.

JVM validation reported 3,823 passes, five existing skips, zero failures/errors
across 547 suites. Repository checks and all 74 AArch64 16 KiB checks passed.
See the [evidence summary](evidence/knowledge-primary-copy-20260913/summary.json).
