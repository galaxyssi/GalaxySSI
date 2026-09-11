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

1. Acquire shared cross-process segment access, before opening a source SQLite
   transaction. Register a new segment UUID durably in the separate SQLite
   segment catalog before creating its file; sync catalog/directory entries.
2. Append bounded encrypted frames and sync the file descriptor.
3. Encrypt the final reference.
4. Commit the reference, segment membership/byte count and derived indexes in the
   existing SQLite transaction, then release shared segment access.

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

## Reclamation and incremental compaction

Schema version 2 adds segment membership and length columns with a covering
index. Existing inline ciphertext remains unchanged. A separate adjacent SQLite
catalog stores random segment UUIDs and a durable maintenance cursor, not memory
content or an in-memory manifest. Registration survives source-transaction
rollback; a process killed before publication therefore leaves a discoverable
orphan. The catalog also reveals segment existence and creation order.

`maintainMemorySegments()` takes exclusive cross-process access. Ordinary memory
operations hold shared access from before SQLite lookup/transaction through
payload consumption/publication. Nested wrappers reuse the same process lock;
upgrading a shared transaction to maintenance is rejected. Locks are released by
the OS on process death. Other database namespaces do not acquire these locks.

A pass visits at most the requested catalog page (default 2, maximum 32), and
moves at most the requested number of live records (default 8, maximum 32) and
1MiB of stored frames. A segment with at least half dead space is eligible for
incremental compaction. Re-encryption streams through 64KiB buffers without
materializing the source JSON/String. The source reference cutover commits before
old files are unlinked and their directory synced. Derived content indexes and
source revisions are unchanged because the plaintext has not changed.

Zero-reference segments are reclaimed. Live records larger than the per-pass
copy budget remain readable but are not compacted by this pass; deletion still
allows their whole segment to be reclaimed. The automatic scheduler is described
below. Starvation of oversized live records, real-device latency under concurrent
access, and storage-pressure behavior remain release gates. File/index metadata is not
tamper-proof; authentication verifies payload references and contents, not every
SQLite page or physical filesystem operation.

## Required before release

- Run JVM framing/authentication tests and real Keystore/SQLite device tests.
- Verify streaming backup/restore, mixed inline/external browse, recall and
  deletion barriers without changing their semantics.
- Validate bounded reclamation/compaction and connect a non-disruptive background
  scheduler, including real OS scheduling and wakeup behavior. Repeated writes
  must not cause permanent unbounded garbage growth.
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
  during that build. That evidence applies to **1.1.69 (955)**, not the later
  maintenance implementation. Current source candidate is **1.1.70 (956)** after
  merging main's separate 1.1.69 update; its verification is still in progress.
- No PR has been published for this incomplete segment stage. Reclamation,
  recovery and real performance remain release gates, not deferred acceptance.

## Maintenance validation (1.1.70 candidate)

- Main at `bae066970` was merged into the branch (merge `ce3f8be43`),
  preserving the empty-window history fix and previously accepted recall report.
- Independent host tests: **31 passed** in 4.743s, including real AES-GCM frames,
  streaming relocation, nested locks, and two real child-process terminations
  that release publication/maintenance locks. This overlaps the Gradle suite;
  it is not an additional 31 unique test cases. The first standalone compiler
  invocation omitted its cached coroutine dependency; the corrected invocation
  and raw results are in `build/memory-segments-v1170-host-compile-retry.log`
  and `build/memory-segments-v1170-host-tests.log`.
- Final frozen-source Android build succeeded in **10m18s**. Full JVM results:
  **3,658 passed, 5 existing skips, zero failures/errors**, 3,663 discovered.
  Log: `build/memory-segments-v1170-final-build.log`. The preceding 24m30s build
  is a development build, not the installed artifact's source freeze.
- Installed only on **SM-T575 / R52R90282TY**, preserving application data and
  pairing. Version **1.1.70 (956)**; APK SHA-256:
  `22481eda1fe0234a8f1af0b1b3639dd33638b3a4f33b503422a7ff6607ca751c`.
  No S26U operation, app uninstall, data reset, or model download was performed.
- **18 real-device tests passed** in 20.244s, including original ciphertext
  preservation through v1-to-v2 schema migration, unrelated v1 namespaces,
  mixed-format normal read/browse/recall, backup/deletion, orphan reclamation,
  bounded compaction, SQL abort and corruption. Raw output:
  `build/memory-segments-v1170-device.log`.
- Two additional **intentional process deaths on the device** were observed:
  immediately before source commit and immediately after commit. Fresh
  instrumentation processes verified rollback/orphan reclamation and committed
  value recovery. Preparation, two verification phases and cleanup passed;
  the intentional crashes are evidence, not passing instrumentation tests.
  Runner: `tools/dev/test-memory-segment-recovery.ps1`. Raw per-phase logs:
  `build/memory-segment-recovery-v1170/segments-recovery-7f0f0fc7345e46bbb4107eb983e6e8e9/`.
  This tests process termination, not battery removal or hardware power loss.
- All **25 existing real-device regressions passed** in 2,057.113s, including
  15 browse tests, eight streaming-backup tests, indexed recall/new-write timing,
  and selected-access timing. Together with the 18 segment tests above, this is
  43 passing device test methods, separate from the intentional crash phases.
  Raw output: `build/memory-segments-v1170-existing-device.log`.
- The new inline recall/write/access run recorded **800/800 samples <=200ms**;
  maximum 193.317385ms. Each operation below has 100 observations at each real
  cardinality. Raw samples and independently checkable summaries are retained in
  `build/memory-segments-v1170-latency.log`. This is a new run, not a replacement
  for the earlier user-accepted 798/800 report with its 201.6/202.4ms outliers.

| Actual rows | Operation | P50 ms | P95 ms | P99 ms | Maximum ms |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1,201 | Warm indexed recall | 73.09 | 81.98 | 87.43 | 88.73 |
| 1,201 | New memory write | 126.09 | 142.45 | 151.17 | 151.85 |
| 1,201 | Single access update | 19.71 | 36.15 | 51.99 | 62.39 |
| 1,201 | Eight access updates | 92.46 | 144.07 | 159.64 | 175.43 |
| 10,001 | Warm indexed recall | 51.22 | 62.53 | 71.61 | 83.50 |
| 10,001 | New memory write | 90.48 | 112.04 | 121.98 | 132.74 |
| 10,001 | Single access update | 33.55 | 49.37 | 70.71 | 79.67 |
| 10,001 | Eight access updates | 145.65 | 174.14 | 192.21 | 193.32 |

These measurements do not certify external-layout latency, threshold crossing,
concurrent maintenance, or 100M-record capacity. The sequential device run is not
a controlled comparison of cardinalities; smaller datasets were not universally
faster. No monotonic latency claim is made.

### Remaining measured performance gaps

- Browse timing is a separate sample set, not part of the 800 observations
  above. At 10,001 rows, a 25-row page recorded **P95 219.61ms, P99 248.49ms,
  maximum 263.39ms; 28/100 exceeded 200ms**. Its functional test passing does
  not waive that latency gate. Eight-row pages and recent-eight reads stayed
  below 200ms. First index construction at that size took 51,543.24ms.
- The real 10,001-row streaming archive round trip preserved contents, counts,
  and order. Archive size was **4,196,934 bytes**; export took **71,200ms**.
  Clear plus restore took **447,109ms**, including approximately 100,246ms to
  clear the existing fixture and 346,863ms for restore. Raw phase evidence:
  `build/memory-segments-v1170-backup-progress.log`. These are bulk-operation
  costs, not individual read/write latency. Streaming correctness does not
  establish acceptable large-corpus backup/restore throughput or concurrent UI
  responsiveness; both remain work items.

At the 1.1.70 checkpoint, automatic scheduling, oversized live-record compaction,
low-storage faults, and new-layout latency remained unfinished. Native disk ANN
and source/index sharding are separate outstanding goals; these candidates are
not a completed 100M-memory delivery.

## Automatic maintenance (1.1.71 candidate)

Startup recovery now registers one unique, persistent WorkManager periodic job
with `KEEP`, a 15-minute interval/initial delay and a device-idle constraint.
Registration is not in normal recall/write calls. The job only handles local
memory ciphertext; it does not use a model, enable global processing, send a
notification, require a network, or publish any memory to another device.
This uses the existing WorkManager dependency. Its periodic interval is not an
exact execution promise: Android may delay idle work. See the official
[periodic work and constraints documentation](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work).

The production worker runs on the IO dispatcher. An absent segment catalog exits
without constructing a memory database. Each step tries both the process operation
lock and cross-process file lock without waiting; contention returns a deferred
result. The same lock order and transaction scope apply to normal operations.
An idle pass checks foreground/cancellation before work, between records and at
64KiB copy boundaries. Returning to the foreground or expiring the five-second
scheduling quantum aborts an unfinished reference transaction, leaves its old
reference valid, and releases locks. Its unpublished tail is cataloged for later
reclamation. A single OS/Keystore/fsync call is not interruptible by this check;
this is cooperative yielding, not a proven 200ms worst-case latency guarantee.

Each step moves at most one record. Successful partial compaction keeps the
durable catalog cursor at that segment until its remaining eligible rows have
been examined. The active destination segment is reused across steps instead of
creating one tiny destination per row. The five-second quantum limits one worker
invocation, not the memory count or the total work needed to finish. WorkManager
retains deferred work for retry; the catalog cursor survives process restart.
Corruption remains an explicit error and retry, not a successful empty sweep.
Fair error isolation across damaged segments and resumable copies of records
larger than 1MiB still require further work.

Validation:

- **42 host tests passed** in 2.493s, including non-blocking cross-process access,
  cancellation between encrypted frames, resumption, and a 10,001-step sweep
  without an action-count ceiling. Logs:
  `build/memory-segments-v1171-host-compile.log` and
  `build/memory-segments-v1171-host-tests.log`.
- Android build succeeded in **23m57s**, including APK and instrumentation APK.
  Full JVM regression: **3,669 passed, five existing skips, zero failures/errors**
  out of 3,674 discovered tests. The focused 42 cases above overlap this suite.
  Log: `build/memory-segments-v1171-build.log`.
- Installed **1.1.71 (957)** only on **SM-T575 / R52R90282TY**, with data-preserving
  replacement and version readback. APK SHA-256:
  `6c48c6d1f2a4a0a4fb89c4b054bcefe455e1b34d416e6ad09bf82feae79800e6`.
  No S26U operation, uninstall, data reset, model download or model-setting
  change was performed.
- **44 real-device tests passed** in 139.856s: 18 segment/maintenance regressions,
  five background-work tests, 14 browse correctness tests and seven streaming
  backup correctness tests. Coverage includes real SQLite lock contention,
  ciphertext cutover rollback, cancellation during a multi-frame copy, continued
  compaction using the same destination, an absent catalog without database
  creation, and durable unique WorkManager registration. Raw output:
  `build/memory-segments-v1171-device.log`.
- This run does not repeat the 10,001-row bulk archive throughput or the inline
  latency matrix. The 1.1.70 measurements remain historical evidence, not
  performance certification of 1.1.71. Registration and the production sweep
  function were exercised; natural OS idle delivery, screen-wakeup latency and
  real UI frame timing still need acceptance.
- Both real process-death recovery checks passed on this build: a kill before
  source commit retained the old value, and a kill after commit retained the new
  value. Fresh processes verified reclamation and recovery, then cleaned only
  their isolated fixture. The two intentional `Process crashed` results are not
  passing tests; preparation, two recovery verifications and cleanup succeeded.
  Log: `build/memory-segment-recovery-v1171.log`; per-phase evidence:
  `build/memory-segment-recovery-v1171/segments-recovery-b0838327a5154e0782f5974c63cb7f46/`.
