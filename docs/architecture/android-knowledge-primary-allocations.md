# Durable primary partition allocation intents

Android 1.1.116 records each new physical primary partition before creating it.
This closes the forward recovery gap where a process dies after a file becomes
durable but before its catalog transaction publishes the partition. Previously,
the catalog rollback also erased the only record of the new file, so ordinary
retirement could never discover it.

## Publication order

1. Generate a random partition identifier and reject an existing physical path.
2. Commit that identifier to the separate allocation journal using SQLite
   DELETE journaling and synchronous EXTRA (since 1.1.117; originally FULL).
   Sync its parent directory before
   returning, including when a prior process created the journal but died before
   syncing that directory entry.
3. Create and sync the body partition, then write and commit its frames.
4. Commit the catalog transaction containing the partition and record references.
5. During idle maintenance, forget committed allocations or reclaim unpublished
   ones. No extra per-record journal write is needed; only file creation logs an
   intent. Foreground commit does not wait for intent cleanup.

The journal resides at `<catalog>.primary.allocations.sqlite`, outside the
directory of body partitions. It stores random identifiers only: no user ID,
title, source, query, plaintext memory or ciphertext body. Its page-cache target
is 256 KiB with mmap disabled. Each operation closes its connection. The existing
catalog schema stays at 16; the separate journal schema is version 1.

## Replay and concurrency

Replay is part of the existing local payload-maintenance worker. It runs only
under the exclusive cross-process payload lease, outside a catalog write
transaction. Writers and old WAL snapshots hold shared leases, so a pending
file cannot be reclaimed while publication or an old reader can reference it.

Each page processes at most eight allocation intents, ordered by identifier.
Catalog partition rows, record references and both source/destination references
of in-progress copy tasks are checked before removal. Registered files must
still be regular files; a missing registered file raises an error rather than
silently acknowledging the intent. Unpublished files use the existing read-pool
retirement and directory-sync path. Main files and all sidecars are checked
before any unlink, rejecting directories and symlinks.

An intent is forgotten only after the physical operation succeeds. Interruption
after unlink but before journal commit is harmless: the next replay observes
the already missing file. Cancellation rolls back journal acknowledgements.
Replay is bounded independently of the number of records and does not enumerate
the partition directory or materialize an entire corpus.

## Limits and validation scope

This is forward recovery for newly journaled allocations. Files orphaned by an
older version before the journal existed are not adopted or deleted merely
because their names resemble partition identifiers. A bounded migration
inventory is still needed for those files. Reclaiming unpublished rows within
an existing live partition remains the responsibility of primary compaction.

The device tests cover committed/rolled-back publication, durable frames without
catalog commit, bounded replay, missing files, cancellation, after-unlink retry,
symlinks, invalid identifiers, unknown legacy files and snapshot deferral.
The host recovery sequence kills the real process after intent persistence,
before catalog publication, after physical unlink and after catalog commit.

This increment does not partition metadata or FTS and does not claim a
100-million-record benchmark or complete-query latency below 200 ms. The wider
memory, Run Kernel, tracing and durable DAG goals remain active.

SQLite documents the distinction between FULL and EXTRA in DELETE-journal mode:
directory synchronization after journal unlink matters for power-loss
durability. The allocation `remember` path explicitly syncs its parent after
the committed insert; replay acknowledgements are idempotent if rolled back.
See [SQLite synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous)
and [atomic commit assumptions](https://www.sqlite.org/atomiccommit.html#hardware_assumptions).

The real-process-death sequence is not a power-cut experiment. Android 1.1.116
still used FULL/DELETE for body writers; Android 1.1.117 applies the stricter
[primary commit policy](android-knowledge-primary-durability.md). The historical
acceptance results below remain for 1.1.116. No physical power-loss acceptance is
claimed here.

## T575 acceptance

The final 1.1.116 APK was installed only on SM-T575 without resetting data. The
build passed with 3,836 JVM cases passed, five skipped, zero failures. Device
groups passed 14 allocation cases, 55 existing partition/reader/copy cases and
97 source/backup/search cases. Four allocation and seven copy process-death
boundaries passed their marker and recovery checks.

One hundred independent new-partition writes measured P50 45.755 ms, P95
59.929 ms and maximum 77.155 ms, all below 200 ms. The first partition write
within an already initialized fixture took 108.307 ms. This benchmark uses
short synthetic bodies and includes the intent commit, directory sync, body
database creation and catalog publication; it excludes App startup, full public
item metadata/FTS indexing, models and UI. It is not a complete-query benchmark.

The retained 10,001 complete records preserved the same digest before and after
reopening. No new compaction was eligible in that run. Three hundred individual
public read/update/restore operations completed within 200 ms, with all 100
modified probes restored and reopened. All 74 AArch64 libraries passed the
16 KB alignment audit. See [the evidence summary](evidence/knowledge-primary-allocations-20260913/summary.json)
for hashes, raw measurements, test names and remaining limitations.
