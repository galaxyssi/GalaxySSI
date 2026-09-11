# Android native disk-vector backend evaluation

Status: candidate evaluation, not integrated or benchmarked. Checked 2026-09-11.
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

No new native dependency or embedding-model download is enabled by this note.
