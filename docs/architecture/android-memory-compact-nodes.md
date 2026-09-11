# Authenticated compact memory nodes

Android candidate 1.1.89 / native adapter 0.5.1 adds versioned compact formats to
the existing encrypted, physically sharded DiskANN store. It does not replace the
source database, download an embedding model or change ASR/QNN execution.

## Representation and quality

- Keep the upstream graph/search algorithm and pinned DiskANN revision
  `a2373e82de8b0edea674736e7fa1c2d55b9a9f44`.
- Apply max-absolute scaling to one normalized vector and use the upstream
  `ScalarQuantizer` borrowed SQ8 API with public constant shift/scale. No training,
  corpus scan, codebook or model-specific assumptions are needed.
- Renormalize the reconstructed direction. Per-vector max-absolute scale cancels
  after normalization and need not be stored.
- Accept SQ8 only when normalized squared-L2 reconstruction error is at most
  `0.0001`. Otherwise try IEEE FP16 via pinned `half` 2.7.1, renormalize, and apply
  the same error check before retaining FP32. Vectors below 128 dimensions use the
  existing small-vector path without quantizer setup. This bound is not a recall
  guarantee. FP16 is not lossless for arbitrary FP32 inputs.
- A 512-dimensional vector payload shrinks from 2,048 to 512 bytes when eligible.
  FP16 uses 1,024 bytes. An encrypted degree-zero node is 2,088 / 552 / 1,064 bytes
  for FP32 / SQ8 / FP16 respectively. Adjacency, SQLite pages,
  source text and the source vector ledger are additional storage.
- Working distance/pruning still uses bounded decoded FP32 nodes and upstream
  SIMD. Direct compressed-distance search and summary/PQ routing remain future
  work; this change is not a claim of zero-decode ANN.

## Durability and privacy

The authenticated node header records format 1 (FP32), 2 (SQ8) or 3 (FP16), dimensions and
degree. Identity, index instance, topology, node ID and revision remain bound by
AES-256-GCM AAD. Unknown formats, noncanonical sizes, invalid dimensions and
excessive adjacency fail rather than becoming empty memory.

Readers support mixed v1/v2/v3 nodes. Existing v1 nodes remain byte-exact FP32 through
adjacency changes; opening an old index performs no migration or full scan. New
eligible nodes store v2/v3. There is not yet a background compactor for existing v1
vectors, so upgrading does not instantly shrink an existing database.

This is forward read compatibility, not downgrade compatibility: older adapters
cannot decode newer node formats. A binary rollback needs a compatible derived
index or a rebuild from the unchanged source/vector ledger. Automatic downgrade
rebuild and online format compaction are not implemented by this change.

SQ8/FP16 bytes remain immutable across adjacency rewrites. The adapter retains and
checks those codes instead of repeatedly quantizing decoded values. Transaction
cache accounting includes both codes and decoded vectors. Sensitive buffers use
`Zeroizing`; the quantizer owns only constant `-1` offsets, not private embeddings.
Whole-process copies and upstream graph scratch are not claimed to be fully wiped.

Transactions, cancellation, checkpoint/source provenance, tombstone visibility,
rollback and physical-shard atomicity retain their existing contracts. No
production pairing, message database or local model is reset by this change.

## Initial device evidence

Initial SQ8-only candidate 1.1.88, SM-T575 native run
`ab2447ca52e2451194bcb0f8993949ed` on 2026-09-12:

- 28 passed, zero failed; one child-process entry deliberately ignored by the
  parent runner and invoked by the process-death tests.
- Native test executable SHA-256:
  `a6f75a67f4af16960b4dbf5006ba0e559af321c7e4503bcb28976005a332c5c8`.
- Four ELF LOAD segments passed 16 KiB alignment checks.
- 320 independent synthetic 512D vectors, 64 independent queries, exact original
  FP32 top-10 ground truth: Recall@10 `0.990625`, query P50/P95/P99
  `10.074 / 17.907 / 26.773 ms`. Graph construction took `3,879.879 ms`.
- 64 separate adjacency commits preserve decoded values and SQ8 bytes exactly;
  reopening preserves values and edges.
- Legacy FP32 injected with an independent synthetic-key encoder remains exact;
  mixed reads and adjacency updates pass. Five authenticated malformed-layout
  cases fail and roll back. Sparse-vector quality fallback remains exact FP32.
- The existing growing point-I/O fixture retains and verifies all 10,032 rows
  (384D), occupies 5,095,424 bytes, and uses a 2 MiB pager/cache target. At 10,000
  seeded rows, read P95 is `1.371 ms`, durable point-write P95 is `41.446 ms`.
  These point writes do not include graph construction or source embedding.

Raw results are preserved in the [native measurement artifact](android-memory-compact-nodes-20260912.json).
Host core regression: 10 passed. The local Windows command excludes SQLite/cache
unit tests that need a Windows C compiler; those remain in all-features Linux CI.

## Larger persisted graphs

The initial SQ8-only frozen ARM64 scale binary has SHA-256
`11fb172b197ad5dada66fb84f7188a0b9f57b2b03748124c3785eb37a029a092`.
It used four physical shards, an 8 MiB cache target and isolated SM-T575 fixtures.
It measures real graph replay, not metadata counters. Every physical vector is
verified after process reopen against its original reconstruction-error bound.

| Measurement | SQ8 candidate |
| --- | ---: |
| Build 1,024 nodes, 64 per committed replay page | 14.841 s |
| 1,024-node query P50 / P95 / P99 | 30.882 / 31.954 / 52.166 ms |
| 1,024-node exact top-eight recall | 253/256 |
| Next 32 independent durable writes P95 / maximum | 181.606 / 192.353 ms |
| Grow from 1,056 to 10,240 nodes | 186.227 s |
| 10,240-node query P95 / recall | 61.805 ms / 249/256 |
| Next 32 independent durable writes P95 / maximum | 192.360 / 200.933 ms |
| 10,272-node query P50 / P95 / P99 | 51.687 / 62.832 / 68.046 ms |
| 10,272-node exact top-eight recall | 250/256 |
| Final fixture bytes | 12,222,464 |
| Largest per-vector squared reconstruction error | 0.000026561 |
| Final measurement peak RSS | 14,868 KiB |

The prior FP32 fixture with the same 10,272 IDs, vector generator and graph
parameters occupies 34,996,224 bytes: this SQ8 fixture is about 65.1% smaller,
including its graph and provenance, not the App source database. This is not a
promise of identical recall: the retained FP32 baseline had 256/256 matches.
Quantization exchanges some nearly tied neighbors. The small 96-node CLI fixture
now has 255/256 matches; its regression requires at least 254/256, while the
independent 320-node SQ8 integration test requires Recall@10 of at least 95%.

The new binary also read the entire retained FP32 fixture without changing a
byte of any reconstructed vector. The first retained-index run had P95 226.290ms
and maximum 503.229ms; a repeated run had P95 57.193ms and maximum 59.155ms.
Both returned 256/256 matches. The cause of the slow first run was not isolated;
it is preserved, not discarded or counted as proof of a 200ms guarantee.

[All 12 scale runs and 422 raw samples](android-memory-compact-scale-20260912.json)
include this slow run, the write tail, exact recall counts and full verification.
Process reopen does not drop operating-system caches. Timings exclude source
database writes, embedding inference, JNI, scheduling and UI. Replay-page batches
are not individual memory writes. The source ledger is unchanged.

## Packaged App verification

- Android 1.1.88, versionCode 974, was built with matching instrumentation APK.
  Gradle completed in 13m 51s: 3,730 unit cases, zero failures/errors, five existing
  skips. All 74 AArch64 libraries passed the 16 KiB alignment audit.
- App APK SHA-256:
  `ce365178307d8203c821be9481bf126b4681bbd8819bf2bd33b0ddf6ebcf86a7`.
- Data-preserving installation on SM-T575 and installed-version checks completed
  before installing/running the matching test APK. Initial 1.1.88 instrumentation
  ran 53 cases: 52 passed, one failed in 141.194s. The new real BGE storage check
  found four graph nodes but none compact: all failed SQ8's error check and stayed
  FP32. That check failed before timing/recall, so no 1.1.88 real-BGE latency or
  accuracy result is claimed. This failed candidate was not submitted as complete.
- Candidate 1.1.89 adds the FP16 middle tier instead of relaxing reconstruction
  accuracy. Its final packaged and device validation is recorded below.

### Final 1.1.89 validation

Android 1.1.89, versionCode 975, completed its build in 13m 57s. The 533 unit
suites contain 3,730 cases with zero failures/errors and five existing skips;
74 native libraries pass 16 KiB alignment. App APK SHA-256:
`df296484ea4b3f0fa56b7f4bdf4cc84ba9992515a528dea51564acea040d74be`.

After data-preserving installation and version verification on SM-T575, its
matching instrumentation APK passed all 53 cases in 168.685s. No other device
was operated, and no production database, pairing or model was replaced.

The existing BGE-small-zh-v1.5 Q8 fixture produces four compact graph nodes,
4,320 encrypted node bytes in total. All three Chinese semantic queries return
the expected top result. Across 100 warm retrievals, P50/P95/P99 are
139/185/213ms. The isolated test uses a 64-token context; production context
settings are unchanged. Three queries are a regression check, not broad recall
acceptance for every embedding model or corpus.

The six foreground retrieval-admission phases retain 192 raw samples with a
maximum of 82ms. The concurrent 204-chunk, 512D background replay takes 3,378ms.
Admission measures handoff/cancellation, not completed embedding or rendered UI
latency. Both the 213ms retrieval tail and the full background duration are
recorded in the final evidence artifact.

## Adaptive-tier native validation

Final native adapter 0.5.1 passed 29 SM-T575 integration cases (one intentional
child entry ignored) in 35.68s and 10 Windows core cases. This includes FP16
outlier reconstruction, 64 separate adjacency commits without drift, reopen,
and authenticated NaN/infinity rejection. The 320-node SQ8 quality case remains
99.0625% Recall@10; P50/P95/P99 are 10.082/18.392/25.755ms.

The final frozen scale binary is
`f604c9840382777a7267773b661d075a983fe274882c5e40a958d137f3d95e5b`.
Its fresh 10,272-node fixture again occupies 12,222,464 bytes and has 250/256
exact held-out top-eight matches. Query P50/P95/P99 are
69.143/84.235/91.899ms. The final 32 independent writes have P95 181.707ms and
maximum 183.293ms; the earlier 1,024-node write stage has P95 210.415ms and
maximum 225.413ms. Those slower samples are retained.

This final binary also verifies every vector of both retained formats:
10,272 FP32 nodes with zero reconstruction error, 256/256 recall and P95
131.377ms; 10,272 SQ8 nodes with maximum squared error 0.000026561, 250/256
recall and P95 84.820ms. Neither retained fixture is rebuilt or migrated.
Transaction cache capacity accounts for FP16's two bytes per dimension through
the existing byte-budget calculation, not a corpus-wide node cap.

[Final native evidence](android-memory-compact-final-20260912.json) includes
nine scale runs, 384 raw graph samples and 256 native integration I/O/query
samples. No slow phase is substituted with another run, and no 200ms universal
latency guarantee is claimed. Native-only point writes and App memory writes
remain different measurements.

## Remaining 100M work

This is a storage-format step, not 100M acceptance. The Kotlin source vector ledger
still stores FP32. Existing graph v1 rows are not compacted. Summary/coarse routing,
compact source projections, adaptive partition splits, bounded migration,
large-scale recall, and 100M unique-record device/storage measurements remain.
Even 100M eligible 512-byte vectors alone require about 47.7 GiB, before graph
edges, source records and metadata. PQ/summary tiers and capacity admission are
still required; an unbounded logical namespace is not unlimited physical storage.
