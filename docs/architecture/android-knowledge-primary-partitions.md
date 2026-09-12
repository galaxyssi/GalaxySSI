# Android knowledge primary partitions

## Scope

New knowledge writes store the complete encoded record in physical encrypted SQLite
partitions. This is the authoritative body store, not a vector-index shard or a
second copy of a canonical JSON corpus. The existing SQLite catalog still owns
identity, source membership, authenticated previews, full-text indexes and vector
change ledgers. Metadata and index partitioning are not included in this phase.

Four opaque-ID buckets select independently rotating files. A partition rotates
after approximately 64 MiB or 65,536 appended records; these are file targets,
not total corpus limits. A single large record may exceed the target. Writer
connections are bounded to four; external body reads share eight permits and
use 2 MiB SQLite caches with mmap disabled. Reads route directly from indexed,
authenticated references and never enumerate every physical database.

Records are split into bounded, surrogate-safe frames, compressed, then sealed
with the existing AES-GCM row-envelope implementation. AAD binds namespace,
logical item, partition, immutable entry and ordinal. Authenticated references
contain expected frame and character counts. Existing record hashes remain
mandatory; missing, reordered or corrupted frames fail closed.

## Publication and recovery

Physical entries are immutable and use independent DELETE-mode rollback journals.
The existing catalog uses WAL; partition files do not add concurrent WAL checkpoint
paths on the bundled SQLite version. All referenced partition transactions commit
with FULL synchronization before the catalog transaction can publish references.
The catalog remains the logical visibility boundary. A failure before publication
preserves the old source, policies and index state, even when some new encrypted
frames already reached disk. Nested failures cannot publish a caught failed write.

This deliberately does not rely on cross-database ATTACH transactions in WAL
mode: SQLite documents that their atomicity is per database, not across the set.
See [SQLite WAL](https://www.sqlite.org/wal.html).

Existing WAL snapshots pin the external-body lease. Replacements preserve old
immutable entries until snapshot readers finish. Fully unreferenced registered
partitions are retired under an exclusive cross-process lease. A durable queue
separates catalog retirement from unlink and makes interrupted deletion retryable.
Mixed live/dead partition compaction and discovery of unregistered files left by
an aborted first publication remain separate follow-up work. No live body is
deleted to reclaim an unverified orphan.

## Migration

Schema 14 adds the physical directory, references, retirement queue and keyset
checkpoint. Existing inline and segment bodies remain readable. Local idle
maintenance migrates at most eight records per page, verifies the new frames,
then atomically publishes references, removes old body references and advances
the checkpoint. Headers, source revisions, IDs, permissions and index watermarks
remain unchanged. Interrupted pages roll back; scheduling yield can commit a
completed prefix. Startup does not copy the complete corpus.

## Validation

`tools/dev/test-knowledge-primary-partitions.ps1` restricts destructive process
death fixtures to the designated SM-T575 and retains all fixture data. Focused
tests cover real physical rotation, Unicode framing, authenticated references,
missing frames, rollback, migration, search/backup snapshots and retirement.
The recovery phase kills the test process before frame commit, between durable
frames and catalog publication, and after catalog commit.

The migration phase reuses the retained 10,001-real-body fixture and checks every
encoded record and logical revision after periodic close/reopen. This is not a
100-million-record benchmark, a universal 200 ms guarantee, or validation of
metadata sharding. Test results must be recorded separately after execution.

### SM-T575 results, 2026-09-13

Android 1.1.111 (997) was built and installed without uninstalling or resetting
the application. The existing 10,001-record synthetic corpus was migrated in
1,251 pages, reopening the store every 250 pages. Migration took 58,344 ms;
the slowest page took 101 ms. Four physical body databases were created.
Every complete encoded record matched the pre-migration stream digest, the
logical source revision was unchanged, and no legacy body references remained.
This measures incremental migration, not a one-record write latency guarantee.

The final focused suite passed all 15 cases, including completed vector documents
remaining readable after physical migration. Three intentional process deaths
were verified at the before-frame, before-catalog and after-catalog boundaries;
fresh processes recovered the expected committed version. The 95-case legacy
suite passed after historical fixture headers were constructed before vector
indexing, rather than rewritten after their fingerprints had been captured.
The 22-case counter suite and 97-case source, backup and search regression suite
also passed. The JVM report contains 3,828 tests: 3,823 passed, five existing skips,
zero failures and zero errors.

The same 10,001-record corpus was then fully replaced with variant
`primary-partitions-v1`, closed, reopened and verified record by record. This
passed in 742.85 seconds, including 689,018 ms for source replacement and
53,681 ms for verification. The preceding unsharded phase measured 327,999 ms
for replacement. These are sequential device observations, not a controlled
thermal or CPU comparison; the observed slowdown remains a performance risk,
not a speedup claim. Source application took 433,161 ms, previous-body preparation
122,002 ms, ownership checks 84,968 ms and observation 39,872 ms. Do not sum
nested phases as independent stages.

The three-case profile also passed. For 100 retained complete-body reads, P95
was 12.799 ms and P99 14.832 ms. For 100 writes inside one existing transaction,
P95 was 54.022 ms and P99 73.658 ms. The write samples exclude the final durable
partition and catalog commits and are not end-to-end durable-write results.
The corpus size and individual record sizes remain part of the result's scope.

Compact raw results, APK hashes, initial fixture failures and limitations are
stored in [the evidence directory](evidence/knowledge-primary-partitions-20260913/summary.json).

During the large Unicode record regression, one process's cumulative VmHWM
reached 1,278,680 KiB. This is a process high-water mark, not isolated partition
cache consumption or a causal attribution to this change. Full-text indexing
and complete single-record materialization still need separate memory profiling.
Bounded partition connections and frame buffers do not imply bounded total
application memory regardless of individual record size.
