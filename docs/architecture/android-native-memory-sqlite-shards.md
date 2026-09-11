# Encrypted native memory node shards

This is the next storage implementation for `galaxyssi-memory-native` **0.2.0**.
It is not yet an activated Android recall backend. It does not change App data,
the existing knowledge database's WAL mode, pairing or ASR/QNN behavior.

This document records the **0.2.0 storage-stage** evidence. The later App bridge
and its separate acceptance are described in
[Android native activation](android-native-memory-activation.md).

## On-disk layout and ownership

One index directory contains `catalog.sqlite` and 1-64 physical
`nodes-00.sqlite` shard files. The power-of-two shard topology is chosen at
creation and authenticated in the catalog. It is not a memory-row count limit;
repartitioning and a higher-level catalog for multiple indexes remain work.

A stable integer mix routes each 64-bit node ID to one shard. Nodes are keyed
by eight-byte IDs, without SQL OFFSET scans. Each node stores a revision and an
AES-256-GCM envelope containing its normalized vector and bounded neighbor IDs.
The catalog stores an authenticated binary format/version, dimensions, topology,
instance ID, generation and node count. The count includes the internal root.
Neither the graph nor its catalog is serialized as a giant JSON document.

The caller supplies a `Zeroizing<[u8; 32]>` key and a 32-byte index identity.
Node authentication binds that identity, the random index instance, dimensions,
topology, node ID and revision. Plaintext vector/neighbor buffers use owned
zeroizing buffers; SQLite receives ciphertext, never those plaintext payloads.
The AES feature also enables key-schedule zeroization. Future Keystore/JNI key
ownership and upstream transient allocations still need lifecycle testing.

This is application-level record encryption, not SQLCipher: schema, node IDs,
revisions, row sizes, file sizes and access patterns are not hidden. Whole-file
rollback/replay by a privileged attacker is not prevented by record AEAD alone.
The App's trusted source revision/deletion checks must remain authoritative.

## Atomic graph updates

All files are attached to **one connection** with a real on-disk main database,
`journal_mode=DELETE` and `synchronous=EXTRA`. SQLite documents cross-attached-DB
atomicity under these conditions; WAL does not provide the same cross-file
commit guarantee. This choice applies only to the new native store.
[SQLite ATTACH](https://www.sqlite.org/lang_attach.html)

A write lease begins `IMMEDIATE`; new nodes, all adjacency changes and the
authenticated metadata generation commit together. A read lease pins the
catalog and node snapshot. Opening validates metadata and root in one snapshot
as well. Cancellation, any operation error or dropping an unfinished lease
rolls back the transaction. A finished/stale lease cannot use or clear a new
owner. A rollback failure discards the connection/key owner and requires reopen.

There is one active lease per store handle. A second connection can read, but
an active reader can block a writer's commit. Busy errors return immediately
instead of waiting in SQLite. The future App scheduler must retry the complete
mutation with backoff off the UI thread; it must not acknowledge a failed commit
or retry only the last graph edge. No latency guarantee follows from this policy.

SQLite uses rollback journals and a super-journal for multi-file atomic commit.
Its guarantees depend on filesystem locking and flush behavior. Process-exit
tests do not prove hardware power-loss safety or coverage of every commit point.
[SQLite atomic commit](https://www.sqlite.org/atomiccommit.html)

## Bounded work and cache

- The configured aggregate pager-cache target is divided across the catalog and
  all shards. It is a target, not a hard whole-process RSS ceiling. Prepared
  statement caching is bounded by topology; `mmap` is disabled.
- A lookup decrypts one node. Envelope length is checked in SQL before copying a
  BLOB into Rust, and dimensions, normalization and adjacency limits are checked
  before use. There is no corpus-sized decoded vector cache.
- Missing files, authentication failure and configuration mismatch fail
  explicitly. Open does not create absent shards or reinterpret them as empty
  memory. Incomplete initial creation remains an invalid candidate directory.
- Closing an inactive store drops the native connection and cipher. A registry
  for total cache budgets across multiple stores is still required.
- The native build explicitly raises SQLite's attach limit to 64; the store
  checks that limit on open. It does not use a hidden fixed row budget.
  [SQLite limits](https://www.sqlite.org/limits.html)
- Newly created files use 16KiB database pages. A `WITHOUT ROWID` table stores
  records in index B-tree cells; large payloads can spill to overflow pages.
  The 16KiB layout accommodates a typical 384D vector plus bounded adjacency
  better than 4KiB pages. This is separate from ELF/Android page alignment and
  does not rewrite existing files. Other dimensions/layouts still need profiling.
  [SQLite file format](https://www.sqlite.org/fileformat2.html)

## Verification scope

`tests/sqlite_store.rs` runs against real SQLite files, not an in-memory mock:

- Encrypted ANN insertion, persistence, reopen and self-query.
- Cross-shard rollback of nodes, graph edges and catalog after partial failure.
- Cancellation, dropped leases, read-only misuse and stale session access.
- Wrong key/identity/dimensions, missing shard, ciphertext and revision damage.
- Competing reader/writer connections, failed commit and full mutation retry.
- A 64-shard topology with sparse 64-bit IDs and a changed cache target.
- Two child-process exits without Rust destructors: one before commit, one
  after commit. Each writes 1,024 nodes across four shards. The parent checks
  journals, authenticated metadata, root edges and physical row counts after
  reopen; it also reads every committed vector.

Test keys and vectors are public synthetic fixtures. The Android runner is
restricted to SM-T575 and `/data/local/tmp`; it does not access private App data.
Raw build, ELF and execution logs are retained per run in
`build/memory-native-evidence/`. Execution results must be recorded after the
tests actually finish; this list describes test coverage, not a passing claim.

## Verified SM-T575 checkpoint

On 2026-09-11, the ARM64 release test executable passed **11 tests, 0 failures**
in **25.11s** on SM-T575. One ignored test is the crash child,
explicitly launched by both process-exit tests, not skipped crash coverage.
Bundled SQLite reports **3.53.2**. All four ELF LOAD segments are 16KiB aligned.
The executable is 3,720,688 bytes, SHA-256
`3309a24fb6d2221046403d480b945661a8ee5921e5fb2953625c83e00789c436`.

The growth test uses synthetic normalized **384D vectors**, four physical
shards, a **2MiB aggregate pager target**, bounded 128-node seed transactions
and 32 individually committed sample writes per level. Timed point reads/writes
include lease acquisition, authentication/encryption and commit; input vector
generation, bulk seeding and subsequent full-content verification are separate.
Each level starts with the listed row count and adds 32 rows during measurement.

| Initial non-root nodes | Point read P95 | Durable insert P95 | Reopen | Files after 32 inserts |
| --- | ---: | ---: | ---: | ---: |
| 100 | 1.398ms | 76.508ms | 4.076ms | 393,216B |
| 1,000 | 1.706ms | 48.255ms | 4.721ms | 2,064,384B |
| 10,000 | 1.934ms | 48.798ms | 4.663ms | 19,169,280B |

All **192** sampled operations were below 200ms in this run; maximum read was
2.641ms and maximum write 83.235ms. Every retained vector was checked after each
level. The final test-process VmRSS was 8,508KiB and VmHWM 8,636KiB. These are
process observations, not a whole-App memory bound or isolated pager usage.
OS file caches were not dropped; reopen is not cold-device I/O.

The previous 4KiB-page run held the same final 10,032 nodes in **47,050,752B**.
Its 10,000-node point read/write P95 was 4.118ms/45.698ms. The new layout reduces
measured file bytes by **59.3%** but does not establish faster writes. The 100-row
write tail was slower than the larger fixtures: fsync/scheduling variance means
strictly monotonic latency with row count has not been proven.

These are point-storage tests, **not** 10,000-node ANN construction/search or BGE
semantic recall. The separate ANN test constructs 64 nodes. They cannot establish
100M capacity, queue/embedding latency, complete hybrid recall or a 200ms App gate.

Raw evidence (including all individual latency samples):

```text
build/memory-native-evidence/60ade47430b140c386e7c479c3e7828b/  # final 16KiB layout
build/memory-native-evidence/7c3efb340b6f455baae7b0eb13c2b3af/  # 4KiB baseline
build/memory-native-evidence/e1df98ff4d884f848e63dee86e168a7c/  # first 10-test pass
build/memory-native-evidence/c90bb9a349b74adb991dd1d222a95b8e/  # test SQL type build failure
```

The failed build used `u64` for SQLite `count(*)`; using SQLite's signed `i64`
fixed that test conversion. Failed evidence and slower measurements are retained.
No App package/data/model was installed, reset, migrated or read by these probes.

The unchanged core adapter also passed **10 Windows host tests** in 2.06s;
that command deliberately excludes SQLite (no Windows C compiler is supplied).
SQLite was tested on Android, while the workflow will run all features on Linux.
The repository guard and all three native-artifact exclusion tests passed locally.
Host evidence: `build/memory-native-evidence/2a19ce8f9477481499cff2493f9d9cce/`.

## Still required for the full goal

Source metadata sharding, durable source-to-index reconciliation, key wrapping,
JNI ownership, deletion/revision barriers, resumable index generation and
repartitioning, streaming backup, production Agent-path activation and real
embedding quality tests are not delivered by this store alone. Increasing-scale
cold/warm read/write/RSS measurements remain necessary. No 100M-row capacity or
200ms production bound has been established. Run Kernel, end-to-end tracing and
ordinary Agent DAG acceptance remain separate unfinished parts of the goal.
