# Android native disk-vector backend evaluation

Status: DiskANN adapter compiled and functionally verified on SM-T575; not
integrated into App recall or validated at production scale. Checked 2026-09-11.
The existing production path uses encrypted vector rows and a transient JVM HNSW
graph. Moving payloads into segments does not remove that graph's RAM requirement.

## Candidates to build and measure

1. **SQLite-backed DiskANN from sqlite-vec.** The upstream release page identifies
   `v0.1.10-alpha.4` as a prerelease with ANN-related fixes. The alpha series adds
   DiskANN and experimental IVF; an earlier alpha fixed deleted data remaining in
   compressed neighbor vectors and noted expensive deletion. It is not adequate
   to test only nearest-neighbor queries: deletion, replacement, crash recovery,
   statement lifetime and private-index residue must be tested before adoption.
   [Upstream releases](https://github.com/asg017/sqlite-vec/releases)
2. **DiskANN3 with an encrypted storage provider.** Upstream exposes a
   `DataProvider` abstraction and disk support. A provider over authenticated
   blocks may fit the existing encrypted ledger better than mapping a plaintext
   index. This is an integration candidate, not a claim that Android NDK builds,
   bounded cache behavior, or our deletion barriers already work.
   [Upstream DiskANN](https://github.com/microsoft/DiskANN)

The current knowledge adapter uses `androidx.sqlite:sqlite-bundled:2.6.2`, not
SQLCipher or an extension-enabled custom native SQLite build. Adding a SQLite
vector extension alone would not encrypt its graph/postings pages. Either a
reviewed encrypted pager or application-authenticated block provider is required;
do not write a plaintext index as a shortcut to a fast native demonstration.

## Acceptance for either candidate

- Pin source/version/license and verify the NDK build, JNI ownership, 16KiB ELF
  alignment, cancellation and background/lock/trim zeroization behavior.
- Use actual persisted unique vectors at increasing cardinalities, with a fixed
  aggregate cache budget across shards, not one independent cache per shard.
- Compare recall against exact top-K, including rare/scoped candidates, deletes,
  conflicts and source revisions. A capped candidate set cannot manufacture a
  low-latency success while silently losing relevant evidence.
- Measure cold reopen, selective and broad query I/O, write/compaction tails,
  build peak RSS and local query embedding separately. Include queue time.
- Reuse real BGE vectors for semantic cases; synthetic normalized vectors are
  suitable for storage/scale fault tests but not semantic-quality evidence.
- Source/lexical hot deltas stay visible before asynchronous vectors are ready.
  A missing, stale or failed native generation must not become missing memory.
- Integrate the selected backend into actual Agent hybrid recall, retaining
  authenticated source checks and bounded evidence fetch. A standalone native
  benchmark or a test-only repository is not delivery of this goal.

## DiskANN adapter checkpoint

The independent [native module](../../apps/android/memory-native/README.md) uses
DiskANN **0.58.0**, pinned to commit
`a2373e82de8b0edea674736e7fa1c2d55b9a9f44`, with locked transitive dependencies.
It uses upstream graph insertion, traversal, pruning and SIMD distance functions.
An authenticated host `NodeStore` supplies one node at a time. Opening reads only
the root, and the adapter does not keep a corpus-sized vector array.

All vectors, queries and the persisted root are normalized. An initial zero-root
experiment failed a self-query regression after 256 inserts; rejecting that root
and using a normalized representative fixed the regression. This requirement
does not replace real embedding recall or root-selection evaluation.

### Verified local evidence

- Windows GNU Rust 1.97.1: **10 tests passed, zero failures or skips**. The suite
  covers malformed nodes, cancellation, 64-bit IDs, reopen, duplicate/root writes,
  and rollback after a neighbor mutation has already occurred. The rollback
  implementation is a test host, not a production durable transaction manager.
- Held-out synthetic quality check: 256 unique 32D vectors, 32 independent
  queries, top-8, search breadth 128. All **256/256** expected hits were returned,
  with 8/8 in every query. These are not real BGE or end-to-end Agent cases.
- A 10,000-row fixture confirms opening reads one root. Those rows are not a
  fully constructed 10,000-node ANN benchmark; that test only checks open I/O.
- Final NDK 29.0.13113456 ARM64 release probe executed on **SM-T575**. It persisted
  64 synthetic 32D vectors in AES-256-GCM fixture files, reopened in separate
  processes, rejected a wrong key, rejected authenticated-ciphertext corruption,
  restored the original and successfully queried again.
- Final probe preparation took **745.539ms** for all 64 inserts. Two fresh-process
  opens read one root each and took **0.237ms / 0.194ms**. Eight self-queries took
  **5.691-9.420ms**. OS file caches were not dropped: these are not cold-device
  latency measurements, a P95 gate, or proof of the 200ms production target.
- All **4 ELF LOAD segments** have 16KiB alignment and congruent offsets/addresses.
  The tested binary is 840,456 bytes, SHA-256
  `18d4738d6803ff0cf3b6ea97e214ef52cdc5ce54ffa11c7407009b5a89810503`.
  This is a standalone executable test, not a JNI or 16KiB-page-device test.
- Three checker regressions verify that only the new native `target/` build tree
  is excluded from source text scanning. Native source and unrelated directories
  named `target` remain checked. Scanning generated object files caused the
  initial repository-check attempt to stall; that attempt was stopped and the
  targeted exclusion was tested rather than disabling the source guard.

Raw evidence remains in these local, Git-ignored directories:

```text
build/memory-native-evidence/1bb822aa47d449e2b36c409c21c8fc2a/host.log
build/memory-native-evidence/6acf93d765c24aedaf0ebd4ee361a7a5/
```

The earlier successful device run remains in
`build/memory-native-evidence/f3ab7a3e8a9c4f2e851aead5d6f72891/`; its binary predates
final formatting. Earlier toolchain and zero-root failures are retained under
`build/native-memory-deps/`. No failed attempt was rewritten as a passing result.

The native workflow now runs locked host tests and formatting checks, but remote
CI has not run for this unpushed checkpoint. Local Windows tests cannot establish
that the Ubuntu job has passed.

### Activation barriers

The standalone probe uses **public test keys and file-per-node fixtures**. Do not
reuse either as production storage. No App database, pairing state or local model
was accessed or changed. The installed App remains 1.1.72 and its recall backend
is unchanged; no native feature flag or embedding-model download is enabled.

Before activation, implement encrypted source/index sharding, the durable host
transaction and snapshot owner, shared fixed-size cache admission, JNI lifetime,
generation/model identity, deletion/revision barriers and background clearing.
Then run real embedding recall, increasing-cardinality construction, process-death
recovery and actual Agent-path performance gates. This checkpoint does **not**
complete the 100M-memory, unified Run Kernel, tracing or long-task DAG goals.
