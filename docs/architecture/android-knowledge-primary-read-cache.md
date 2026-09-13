# Bounded primary partition read connections

Android 1.1.115 reuses primary-body read connections across record reads. The
catalog, metadata and FTS are unchanged. This improves the physical partition
read path; it is not completion of full metadata/FTS sharding or acceptance at
100 million records.

## Evidence for this step

The retained 10,001-real-record fixture on SM-T575 exposed a large gap between
individual reads and complete retrieval. With Android 1.1.114, five warm samples
after one warmup measured 34.973 ms at the slowest sample for FTS selection of
256 candidates, 1,576.626 ms for reading 256 complete records, and 1,764.973 ms
for a common-term lexical query. These are small-sample diagnostics, not a
production P95 guarantee. The preceding 300 individually timed API operations
under 200 ms did not establish complete retrieval latency under 200 ms.

Code inspection showed that every primary body read opened, configured and
closed its physical SQLite database. A query could repeat that work 256 times
even when its candidates shared one partition. Splitting the FTS table further
would not by itself remove this measured bottleneck.

## Resource model

One process-wide pool bounds active plus idle primary read connections to eight.
The existing SQLite pager target is 2 MiB per connection, with mmap disabled.
Sixteen MiB is the aggregate configured pager target, not a total application RSS
ceiling; connection metadata, active frame buffers and full returned records are
additional allocations. The bound does not grow with partition or corpus count.

Each checkout exclusively owns one connection until its cursor is closed. Idle
connections keep compiled SQL and ciphertext pages only. Statement reset releases
read locks and results, and clearBindings removes bound values before reuse.
No decoded memory, title, excerpt, vector or search result is cached here.
No read transaction remains pinned on a pooled connection between records.
The separate catalog snapshot and existing cross-process payload lease continue
to define logical visibility and protect old immutable bodies.

If all slots are busy, a caller waits interruptibly. A closing resource still
occupies its slot until close completes. Factories, file validation and resource
close run outside the pool's bookkeeping lock. Idle entries are evicted in LRU
order. Failed reads discard their connection, including authentication errors.
Ordinary writer-owned reads still use their pending writer connection so they
can observe their own uncommitted body frames.

## Identity, retirement and cleanup

Cache keys include the root and physical path. On checkout, lstat verifies a
regular file and its device/inode identity. A missing file cannot be read through
an unlinked cached handle; a replaced inode must be reopened and authenticated;
a symbolic link cannot reuse a previous regular-file cache entry. Record hashes,
reference/frame authentication, contiguous ordinals and bounded decoding remain
mandatory on every read.

The root is canonicalized once per partition owner so equivalent root paths do
not allocate duplicate cache entries or bypass retirement invalidation.

Physical retirement invalidates the exact file before unlink and refuses an
active lease. Owner close invalidates its root; busy entries are discarded when
their readers release them. The existing semantic runtime background/trim entry
point queues cache disposal on a separate cleanup thread, coalescing repeated
requests. Idle connections close there, not on the UI thread; active readers
are not forcibly closed mid-operation.

## Verification scope

The retained before/after profile uses the same corpus and queries without
reseeding or reducing candidates. The after profile also records connection
opens/reuses and full-body decryption counts outside the timed samples. The
functional suites cover reuse across keys, rotation beyond cache capacity,
pending writes, rollback, external corruption, inode replacement, missing files,
symlinks, retirement, memory-pressure cleanup and concurrent catalog snapshots.

Generic pool tests exercise waiting, interruption, failed opens/reads/closes,
shutdown during an open, active invalidation and capacity during close. Existing
primary compaction/copy and real process-death tests remain applicable.

The remaining architecture still needs metadata/index partitioning with bounded
query work, full-record memory profiling and a much larger real corpus. FTS query
fanout, ranking cost and cryptographic identity checks must be measured at those
scales. A read connection cache is not a universal sub-200 ms retrieval guarantee.

## Retained-device comparison

Both versions used the same 10,001 complete-record corpus on SM-T575, without
reseeding or changing candidate counts. Each diagnostic discarded one warmup
and measured five samples. P95 here is the maximum of those five samples, not a
statistically established production percentile. Times below are milliseconds.

| Operation | 1.1.114 P50 | 1.1.115 P50 | 1.1.114 P95 | 1.1.115 P95 |
| --- | ---: | ---: | ---: | ---: |
| FTS select 256 | 30.476 | 28.820 | 34.973 | 34.569 |
| Read 256 complete records | 1451.033 | 1321.474 | 1576.626 | 1763.854 |
| Common-term lexical query | 1683.647 | 1565.516 | 1764.973 | 1672.365 |

The six complete-record batches opened four connections and reused them 1,532
times; the subsequent six lexical queries opened none and reused them 1,536
times. Each operation still decrypted 1,536 full bodies across six samples.
Connection churn is removed, but total retrieval remains far above 200 ms, and
the slowest batch-read sample regressed. Cold first samples were also slower
than the baseline. This change must not be described as meeting the latency
target; further measurements must separate authentication, decoding, candidate
materialization and ranking rather than assume SQLite opens explain all cost.

An earlier prototype incorrectly evicted an idle entry before using free pool
capacity, effectively keeping one slot. Three pool tests failed, and the
prototype lexical query reached 2,786.740 ms. That prototype was not committed.
The corrected allocation order uses matching idle entries, then empty capacity,
then LRU eviction. Its failed test XML and device measurements remain alongside
the corrected evidence rather than being overwritten.

## Acceptance results

The corrected APK and test APK were installed only on SM-T575 without a reset.
The build and repository gate passed, as did 74 AArch64 library alignment checks.
JVM results were 3,836 passed, five skipped, zero failures; the 13 new pool cases
all passed. Device regression groups passed 55 reader/partition/copy/snapshot
cases and 97 source/backup/search cases. Seven intentional process deaths and
seven preparation/recovery checks passed at the existing copy boundaries.

The retained 10,001-record corpus preserved its complete encoded-record digest
before and after reopening. This check had no newly eligible compaction work;
it must not be counted as a new full-corpus relocation benchmark. The 300 single
API operations (100 reads, updates and restores each) all completed within
200 ms, and the 100 probe records were restored and reopened. These individual
API results do not override the complete-query limitation reported above.

Raw metrics, failed prototype evidence, test names, APK hashes and limitations
are recorded in [the evidence summary](evidence/knowledge-primary-readers-20260913/summary.json).
